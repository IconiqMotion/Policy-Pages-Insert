#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$HOME/shared/policies"
TPL_DIR="$WORKDIR/templates"
BUILD_ROOT="$WORKDIR/build"

CONFIG_ENV="$HOME/.config/policies/env"
[[ -f "$CONFIG_ENV" ]] && source "$CONFIG_ENV"

: "${GH_TOKEN:?GH_TOKEN not set}"
: "${OWNER:?OWNER not set}"
: "${REPO:?REPO not set}"
: "${BRANCH:=main}"

PHP_BIN="$(command -v php)"
CURL_BIN="$(command -v curl)"
[[ -n "${PHP_BIN:-}" && -n "${CURL_BIN:-}" ]] || { echo "php/curl missing"; exit 1; }

EFFECTIVE_DATE="${EFFECTIVE_DATE:-$(date +%Y-%m-%d)}"
COURT_DISTRICT="${COURT_DISTRICT:-ת״א}"
ROBOTS_INDEX="${ROBOTS_INDEX:-index,follow}"

DRY_RUN=false
SITES=()

usage(){ echo "Usage: $0 [--dry-run] --sites a.com,b.co.il | --sites-file /path/list.txt"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift;;
    --sites) IFS=',' read -r -a SITES <<< "${2:-}"; shift 2;;
    --sites-file) mapfile -t SITES < "${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done
(( ${#SITES[@]} )) || { echo "חסר --sites או --sites-file"; exit 1; }

mkdir -p "$WORKDIR" "$TPL_DIR" "$BUILD_ROOT"

fetch_repo_assets() {
  echo "==> Fetch $OWNER/$REPO@$BRANCH"
  $CURL_BIN -fLsS -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github.raw" \
    "https://api.github.com/repos/$OWNER/$REPO/contents/scripts/policy_inject.php?ref=$BRANCH" \
    -o "$WORKDIR/policy_inject.php"
  chmod 0755 "$WORKDIR/policy_inject.php"

  local listing
  listing="$($CURL_BIN -fLsS -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$OWNER/$REPO/contents/templates?ref=$BRANCH")"

  echo "$listing" | grep -q '"name": *"manifest.json"' || { echo "manifest.json חסר"; exit 1; }
  $CURL_BIN -fLsS -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github.raw" \
    "https://api.github.com/repos/$OWNER/$REPO/contents/templates/manifest.json?ref=$BRANCH" \
    -o "$TPL_DIR/manifest.json"

  # משיכת כל קבצי ה-PHP מהתיקיה
  while read -r name; do
    name="${name%\"}"; name="${name#\"}"
    [[ "$name" == *.php ]] || continue
    $CURL_BIN -fLsS -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github.raw" \
      "https://api.github.com/repos/$OWNER/$REPO/contents/templates/$name?ref=$BRANCH" \
      -o "$TPL_DIR/$name"
  done < <(echo "$listing" | grep -o '"name": *"[^"]*"' | cut -d'"' -f4)

  echo "==> Done"
}

ensure_htaccess_rules() {
  local docroot="$1"
  local robots="${2:-index,follow}"
  local ht="$docroot/.htaccess"
  local tmp="$ht.tmp"
  local start="# BEGIN POLICIES"
  local end="# END POLICIES"

  if [[ ! -f "$ht" ]]; then
    cat >"$ht" <<'WPBASE'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
WPBASE
    chmod 0644 "$ht"
  fi

  awk -v s="$start" -v e="$end" '
    $0 ~ s {inb=1; next}
    $0 ~ e {inb=0; next}
    !inb
  ' "$ht" > "$tmp" && mv "$tmp" "$ht"

  cat >> "$ht" <<HT
# BEGIN POLICIES
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^(privacy|terms|accessibility|shipping|returns)/?$ policies/\$1.php [L,QSA]
</IfModule>

<IfModule mod_headers.c>
<FilesMatch "^(privacy|terms|accessibility|shipping|returns)\.php$">
  Header set Cache-Control "no-store, no-cache, must-revalidate, max-age=0"
  Header set Pragma "no-cache"
  Header set X-Robots-Tag "$robots"
</FilesMatch>
Header always set X-Content-Type-Options "nosniff"
Header always set X-Frame-Options "SAMEORIGIN"
Header always set Referrer-Policy "strict-origin-when-cross-origin"
</IfModule>
# END POLICIES
HT
}

deploy_one_site() {
  local domain="$1"
  local site_root="$HOME/$domain"
  local install_dir="$site_root/policies"

  echo "=== $([[ $DRY_RUN == true ]] && echo 'DRY ' )DEPLOY → $domain"
  [[ -d "$site_root" ]] || { echo "!! skip: $site_root not found"; return 0; }

  local work="$BUILD_ROOT/$domain"
  rm -rf "$work" && mkdir -p "$work"

  # מעתיקים את התבניות ל-work (קבצי PHP "partials")
  cp -f "$TPL_DIR"/*.php "$work/" || true

  # מריצים אינג'קט (יבנה __build_<slug>.php)
  "$PHP_BIN" "$WORKDIR/policy_inject.php" \
    --dir "$work" \
    --manifest "$TPL_DIR/manifest.json" \
    --site-root "$site_root" \
    --effective-date "$EFFECTIVE_DATE" \
    --court-district "$COURT_DISTRICT" \
    --index-policy "$ROBOTS_INDEX" \
    $([[ $DRY_RUN == true ]] && echo --dry-run || true)

  if [[ "$DRY_RUN" == true ]]; then
    echo "DRY-RUN: אין העתקה ל-$install_dir"
    return 0
  fi

  mkdir -p "$install_dir"
  shopt -s nullglob
  for f in "$work"/__build_*.php; do
    base="$(basename "$f" | sed 's/^__build_//')"
    tmp="$install_dir/$base.tmp"
    cp -f "$f" "$tmp" && mv -f "$tmp" "$install_dir/$base"
    chmod 0644 "$install_dir/$base"
  done
  shopt -u nullglob

  ensure_htaccess_rules "$site_root" "$ROBOTS_INDEX"
  echo "OK: $domain"
}

fetch_repo_assets
for d in "${SITES[@]}"; do deploy_one_site "$d"; done
echo "DONE."
