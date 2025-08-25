#!/usr/bin/env bash
set -euo pipefail

PHP_BIN="${PHP_BIN:-php}"         # אם צריך: PHP_BIN="/usr/local/bin/php"
REPO_DIR="$HOME/shared/policies"
ZIP="$REPO_DIR/policy_templates_he.zip"
MANIFEST="$REPO_DIR/manifest.json"
WORKDIR="$REPO_DIR/work"
DATE="$(date +%Y-%m-%d)"

# קבע כאן את רשימת האתרים לפיילוט:
SITES=(
  "amira-beautyclinic.co.il"
  "ea-manpower.co.il"
)

# נתיב הבסיס (התאם אצלך אם שונה)
HOME_BASE="$HOME"

# חילוץ התבניות (תמיד מנקה יעדים זמניים)
rm -rf "$WORKDIR" && mkdir -p "$WORKDIR"
unzip -o "$ZIP" -d "$WORKDIR"

# פונקציה להחלת הכללים ב-.htaccess
ensure_htaccess_rules() {
  local site_root="$1"
  local ht="$site_root/.htaccess"

  # צרף כללים רק אם לא קיימים
  if ! grep -q "## policies-routes ##" "$ht" 2>/dev/null; then
    cat >> "$ht" <<'EOF'

## policies-routes ##
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule ^privacy/?$ privacy.html [L]
RewriteRule ^terms/?$ terms.html [L]
RewriteRule ^shipping/?$ shipping.html [L]
RewriteRule ^returns/?$ returns.html [L]
RewriteRule ^accessibility/?$ accessibility.html [L]
</IfModule>
## end-policies-routes ##
EOF
  fi
}

# לולאה על האתרים
for domain in "${SITES[@]}"; do
  echo "===> Deploying to: $domain"

  site_root="$HOME_BASE/$domain"
  if [ ! -d "$site_root" ]; then
    echo "!! skip: $site_root not found"
    continue
  fi

  # העתקת הקבצים
  cp -f "$WORKDIR/"*.html "$site_root/"

  # הזרקת placeholders באמצעות PHP (להלן policy_inject.php)
  $PHP_BIN "$REPO_DIR/policy_inject.php" --dir "$site_root" --manifest "$MANIFEST" \
    --effective-date "$DATE" \
    --court-district "ת״א" \
    --index-policy "index,follow"

  # htaccess
  ensure_htaccess_rules "$site_root"

  echo "OK: $domain"
done

echo "Done."
