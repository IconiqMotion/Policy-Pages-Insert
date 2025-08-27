#!/usr/bin/env php
<?php
ini_set('display_errors', '1');
error_reporting(E_ALL);

function argval($key, $default=null) {
    foreach ($GLOBALS['argv'] as $i => $a) {
        if ($a === $key && isset($GLOBALS['argv'][$i+1])) return $GLOBALS['argv'][$i+1];
        if (str_starts_with($a, $key.'=')) return substr($a, strlen($key)+1);
    }
    return $default;
}
function hasWoo($siteRoot) {
    return is_dir("$siteRoot/wp-content/plugins/woocommerce")
        || is_file("$siteRoot/wp-content/plugins/woocommerce/woocommerce.php");
}
function loadWpContext($siteRoot) {
    $wp = "$siteRoot/wp-load.php";
    if (is_file($wp)) { require_once $wp; return true; }
    return false;
}
function safeGetOption($name, $default='') {
    return function_exists('get_option') ? (get_option($name) ?: $default) : $default;
}
function replacePlaceholders($text, $map, $placeholders) {
    foreach ($placeholders as $key) {
        $val = $map[$key] ?? '';
        $text = str_replace("{{$key}}", $val, $text);
        $text = str_replace("%%{$key}%%", $val, $text);
        $text = str_replace("__{$key}__", $val, $text);
        $text = preg_replace('/\b'.preg_quote($key,'/').'\b/u', $val, $text);
    }
    return $text;
}

$tplDir     = rtrim(argval('--dir'), '/');            // היכן התבניות (נשלפות מהריפו)
$manifest   = argval('--manifest');                   // manifest.json
$siteRoot   = rtrim(argval('--site-root'), '/');      // שורש WP
$effDate    = argval('--effective-date', date('Y-m-d'));
$court      = argval('--court-district', 'ת״א');
$robots     = argval('--index-policy', 'index,follow');
$dryRun     = in_array('--dry-run', $argv, true);

if (!$tplDir || !$manifest || !$siteRoot) {
    fwrite(STDERR, "Usage: --dir <templates-dir> --manifest <path> --site-root <wp-root> [--effective-date] [--court-district] [--index-policy] [--dry-run]\n");
    exit(2);
}
if (!is_dir($tplDir) || !is_file($manifest) || !is_dir($siteRoot)) {
    fwrite(STDERR, "Invalid paths: templates / manifest / site-root\n");
    exit(2);
}

$man = json_decode(file_get_contents($manifest), true);
if (!$man || empty($man['files']) || empty($man['placeholders'])) {
    fwrite(STDERR, "Bad manifest structure\n");
    exit(2);
}
$defaults = $man['defaults'] ?? [];

$domain  = basename($siteRoot);
$siteUrl = "https://".$domain;

$usingWp = loadWpContext($siteRoot);
$map = [
    'BUSINESS_NAME' => $usingWp ? safeGetOption('blogname', $domain) : $domain,
    'SITE_URL'      => $usingWp ? (safeGetOption('home', $siteUrl)) : $siteUrl,
    'EMAIL'         => $usingWp ? safeGetOption('admin_email', '') : '',
    'PHONE'         => '',
    'ADDRESS'       => '',
    'EFFECTIVE_DATE'=> $effDate,
    'INDEX_POLICY'  => $robots,
    'COURT_DISTRICT'=> $court,
    'DELIVERY_HANDLE_DAYS'       => $defaults['DELIVERY_HANDLE_DAYS']      ?? '',
    'DELIVERY_PRICE_HOME'        => $defaults['DELIVERY_PRICE_HOME']       ?? '',
    'DELIVERY_DAYS_HOME'         => $defaults['DELIVERY_DAYS_HOME']        ?? '',
    'DELIVERY_PRICE_REGISTERED'  => $defaults['DELIVERY_PRICE_REGISTERED'] ?? '',
    'DELIVERY_DAYS_REGISTERED'   => $defaults['DELIVERY_DAYS_REGISTERED']  ?? '',
    'CANCEL_WITHIN_DAYS'         => $defaults['CANCEL_WITHIN_DAYS']        ?? '',
    'REFUND_DAYS'                => $defaults['REFUND_DAYS']               ?? ''
];
$overrides = "$siteRoot/policies/.overrides.json";
if (is_file($overrides)) {
    $ov = json_decode(file_get_contents($overrides), true);
    if (is_array($ov)) $map = array_merge($map, $ov);
}

$woo = hasWoo($siteRoot);
$processed = 0;

foreach ($man['files'] as $item) {
    $src = is_array($item) ? ($item['src'] ?? '') : $item;
    $slug = is_array($item) ? ($item['slug'] ?? pathinfo($src, PATHINFO_FILENAME)) : pathinfo($src, PATHINFO_FILENAME);
    $requires = is_array($item) ? ($item['requires'] ?? '') : '';

    if ($requires === 'woocommerce' && !$woo) {
        continue;
    }

    $srcPath = $tplDir.'/'.$src;
    if (!is_file($srcPath)) {
        fwrite(STDERR, "Missing template: $srcPath\n");
        continue;
    }

    $body = file_get_contents($srcPath);
    // בטיחות: אם בטעות הכניסו תגיות PHP בתבנית, נסיר אותן כדי לא לשבור את העיטוף
    $body = preg_replace('/<\?php.*?\?>/s', '', $body);

    $body = replacePlaceholders($body, $map, $man['placeholders']);

    $wrapped = "<?php\n"
        . "\$docroot = dirname(__DIR__);\n"
        . "\$using_wp = false;\n"
        . "if (is_file(\$docroot.'/wp-load.php')) { require_once \$docroot.'/wp-load.php'; if (function_exists('get_header') && function_exists('get_footer')) { \$using_wp = true; get_header(); } }\n"
        . "@header('X-Robots-Tag: ".addslashes($map['INDEX_POLICY'])."');\n"
        . "?>\n"
        . "<main class=\"policy-page\" style=\"max-width:900px;margin:40px auto;padding:0 16px;\">\n"
        . $body . "\n"
        . "</main>\n"
        . "<?php if (\$using_wp) { get_footer(); } ?>\n";

    $destPhp = $tplDir.'/__build_'.$slug.'.php';
    if ($dryRun) {
        $processed++;
        continue;
    }
    if (file_put_contents($destPhp, $wrapped) === false) {
        fwrite(STDERR, "Write failed: $destPhp\n");
        exit(3);
    }
    @chmod($destPhp, 0644);
    $processed++;
}

echo ($dryRun
    ? "Injected placeholders in $processed files under $siteRoot\n"
    : "Built $processed files under $siteRoot\n");
