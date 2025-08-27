#!/usr/bin/env bash
set -euo pipefail

# אתרי פיילוט (תוכל להרחיב אח"כ)
SITES=("amira-beautyclinic.co.il" "ea-manpower.co.il")

WORKDIR="$HOME/shared/policies"
TEMPLATES="$WORKDIR/templates_extracted"
MANIFEST="$WORKDIR/manifest.json"
PHP_BIN="$(command -v php)"

EFFECTIVE_DATE="$(date +%Y-%m-%d)"
COURT_DISTRICT="ת״א"
ROBOTS_INDEX="index,follow"

OVERWRITE=0   # 0=לא לדרוס קיים, 1=לדרוס

has_wc() {
  local site_root="$1"
  # 1) אם wp-cli קיים - נשתמש בו:
  if command -v wp >/dev/null 2>&1; then
    wp plugin is-active woocommerce --path="$site_root" >/dev/null 2>&1 && return 0
    wp plugin is-installed woocommerce --path="$site_root" >/dev/null 2>&1 && return 0
  fi
  # 2) זיהוי תקייה של התוסף:
  [ -d "$site_root/wp-content/plugins/woocommerce" ] && return 0
  [ -f "$site_root/wp-content/plugins/woocommerce/woocommerce.php" ] && return 0
  return 1
}

remove_shop_pages_if_needed() {
  local site_root="$1"
  if ! has_wc "$site_root"; then
    rm -f "$site_root"/shipping.html "$site_root"/returns.html \
          "$site_root"/shipping.php  "$site_root"/returns.php || true
    echo "   (No WooCommerce) removed shipping/returns pages if existed."
  else
    echo "   WooCommerce detected – keeping shipping/returns."
  fi
}

for domain in "${SITES[@]}"; do
  site_root="$HOME/$domain"
  echo "=== DEPLOY to $domain ==="
  if [ ! -d "$site_root" ]; then
    echo "!! skip: $site_root not found"
    continue
  fi

  # העתקת תבניות HTML (לפני ההזרקה/המרה)
  if [ "$OVERWRITE" -eq 1 ]; then
    cp -f "$TEMPLATES"/*.html "$site_root/"
  else
    cp -n "$TEMPLATES"/*.html "$site_root/" || true
  fi

  # הזרקת placeholders
  "$PHP_BIN" "$WORKDIR/policy_inject.php" \
    --dir "$site_root" \
    --manifest "$MANIFEST" \
    --effective-date "$EFFECTIVE_DATE" \
    --court-district "$COURT_DISTRICT" \
    --index-policy "$ROBOTS_INDEX"

  # הסרה במקרה שאין WooCommerce
  remove_shop_pages_if_needed "$site_root"

  # המרה ל־PHP עם header/footer (סעיף ב' למטה)
  "$PHP_BIN" "$WORKDIR/wrap_wp.php" --dir "$site_root"

  echo "-- HTML/PHP files after deploy:"
  ls -1 "$site_root"/*.{html,php} 2>/dev/null || echo "(no html/php files?)"
done
