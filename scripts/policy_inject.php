#!/usr/bin/env php
<?php
/**
 * policy_inject.php
 * Usage:
 *   php policy_inject.php --dir /home/user/amira-beautyclinic.co.il --manifest ~/shared/policies/manifest.json \
 *       --effective-date 2025-08-25 --court-district "ת״א" --index-policy "index,follow"
 */

ini_set('display_errors', 'stderr');

function arg($key, $default=null) {
  foreach ($GLOBALS['argv'] as $i => $a) {
    if (strpos($a, "--$key=") === 0) {
      return substr($a, strlen("--$key="));
    } elseif ($a === "--$key" && isset($GLOBALS['argv'][$i+1])) {
      return $GLOBALS['argv'][$i+1];
    }
  }
  return $default;
}

$dir = rtrim(arg('dir'), '/');
$manifestPath = arg('manifest');
if (!$dir || !$manifestPath || !is_dir($dir) || !is_file($manifestPath)) {
  fwrite(STDERR, "Missing --dir or --manifest\n");
  exit(1);
}

$manifest = json_decode(file_get_contents($manifestPath), true);
$defaults = $manifest['defaults'] ?? [];

$domain = basename($dir);
$scheme = 'https';
$siteUrl = "$scheme://$domain";

$place = [
  'SITE_URL' => $siteUrl,
  'BUSINESS_NAME' => preg_replace('/[-_.]/', ' ', strtok($domain, '.')), // fallback
  'EMAIL' => "info@$domain",
  'PHONE' => '',
  'ADDRESS' => '',
  'EFFECTIVE_DATE' => arg('effective-date', date('Y-m-d')),
  'INDEX_POLICY' => arg('index-policy', $defaults['INDEX_POLICY'] ?? 'index,follow'),
  'COURT_DISTRICT' => arg('court-district', 'ת״א'),

  'DELIVERY_HANDLE_DAYS' => $defaults['DELIVERY_HANDLE_DAYS'] ?? '2',
  'DELIVERY_PRICE_HOME' => $defaults['DELIVERY_PRICE_HOME'] ?? '35',
  'DELIVERY_DAYS_HOME' => $defaults['DELIVERY_DAYS_HOME'] ?? '3-5',
  'DELIVERY_PRICE_REGISTERED' => $defaults['DELIVERY_PRICE_REGISTERED'] ?? '20',
  'DELIVERY_DAYS_REGISTERED' => $defaults['DELIVERY_DAYS_REGISTERED'] ?? '5-7',
  'CANCEL_WITHIN_DAYS' => $defaults['CANCEL_WITHIN_DAYS'] ?? '14',
  'REFUND_DAYS' => $defaults['REFUND_DAYS'] ?? '7',
];

// ניסיון למשוך נתונים מ־WP-CLI אם קיים wp-config.php
function find_wp_root($dir) {
  if (file_exists("$dir/wp-config.php")) return $dir;
  if (file_exists("$dir/public_html/wp-config.php")) return "$dir/public_html";
  return null;
}
$wpRoot = find_wp_root($dir);

function wp_cli($path, $cmd) {
  $full = "wp --path=".escapeshellarg($path)." $cmd";
  $out = [];
  $ret = 0;
  @exec($full, $out, $ret);
  return $ret === 0 ? trim(implode("\n", $out)) : null;
}

if ($wpRoot) {
  $bn = wp_cli($wpRoot, 'option get blogname');
  if ($bn) $place['BUSINESS_NAME'] = $bn;
  $home = wp_cli($wpRoot, 'option get home');
  if ($home) $place['SITE_URL'] = rtrim($home, '/');
  $adm = wp_cli($wpRoot, 'option get admin_email');
  if ($adm) $place['EMAIL'] = $adm;
}

// החלפה בקבצי ה-HTML
$files = glob("$dir/*.html");
foreach ($files as $f) {
  $html = file_get_contents($f);
  foreach ($place as $k => $v) {
    $html = str_replace("{{$k}}", $v, $html);
  }
  file_put_contents($f, $html);
}

echo "Injected placeholders in ".count($files)." files under $dir\n";
