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

  local RULES='## policies-routes ##
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule ^privacy/?$ privacy.html [L]
RewriteRule ^terms/?$ terms.html [L]
RewriteRule ^accessibility/?$ accessibility.html [L]
RewriteRule ^shipping/?$ shipping.html [L]
RewriteRule ^returns/?$ returns.html [L]
</IfModule>
## end-policies-routes ##'

  # אם כבר קיימים – לא לגעת
  if grep -q "## policies-routes ##" "$ht" 2>/dev/null; then
    return
  fi

  # אם יש בלוק וורדפרס – נכניס לפניו
  if grep -q "^# BEGIN WordPress" "$ht" 2>/dev/null; then
    cp "$ht" "$ht.bak.$(date +%s)"
    awk -v add="$RULES\n" '
      BEGIN { inserted=0 }
      /^# BEGIN WordPress/ && !inserted { print add; inserted=1 }
      { print }
      END { if(!inserted) print add }
    ' "$ht" > "$ht.tmp" && mv "$ht.tmp" "$ht"
  else
    # אין בלוק וורדפרס: נוסיף לראש הקובץ (או ניצור חדש)
    cp "$ht" "$ht.bak.$(date +%s)" 2>/dev/null || true
    { echo "$RULES"; echo; cat "$ht" 2>/dev/null; } > "$ht.tmp" && mv "$ht.tmp" "$ht"
  fi
}

# בדיקה שהאתר הוא לא אתר עם ווקמורס
has_woocommerce() {
  local site_root="$1"
  local wp_root=""
  if [ -f "$site_root/wp-config.php" ]; then
    wp_root="$site_root"
  elif [ -f "$site_root/public_html/wp-config.php" ]; then
    wp_root="$site_root/public_html"
  fi
  if [ -z "$wp_root" ]; then
    return 1
  fi
  # אם WP-CLI קיים – נשתמש בו
  if command -v wp >/dev/null 2>&1; then
    if wp --path="$wp_root" plugin is-active woocommerce >/dev/null 2>&1; then
      return 0
    fi
    # fallback: זיהוי עמודים אופייניים
    if wp --path="$wp_root" post list --post_type=page --name__in=shop,cart,checkout,my-account --format=ids | grep -q '[0-9]'; then
      return 0
    fi
  else
    # בלי WP-CLI: בדיקת תיקיית תוסף
    if [ -d "$wp_root/wp-content/plugins/woocommerce" ]; then
      return 0
    fi
  fi
  return 1
}



# לולאה על האתרים
for domain in "${SITES[@]}"; do
  echo "===> Deploying to: $domain"

  site_root="$HOME_BASE/$domain"
  if [ ! -d "$site_root" ]; then
    echo "!! skip: $site_root not found"
    continue
  fi

    # קבצים בסיסיים לכולם
    FILES=( "privacy.html" "terms.html" "accessibility.html" )

    # הוסף קבצי חנות רק אם יש WooCommerce/עמודי חנות
    if has_woocommerce "$site_root"; then
      FILES+=( "shipping.html" "returns.html" )
    fi

    # העתקה ופרמישנים (מעתיקים רק אם הקובץ קיים ב-WORKDIR)
    for f in "${FILES[@]}"; do
      if [ -f "$WORKDIR/$f" ]; then
        cp -f "$WORKDIR/$f" "$site_root/$f"
        chmod 0644 "$site_root/$f"
      fi
    done


echo "Done."
