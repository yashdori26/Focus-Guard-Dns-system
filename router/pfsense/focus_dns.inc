<?php
/**
 * focus_dns.inc
 * FocusDNS pfSense Integration Module
 * Location: /usr/local/pkg/focus_dns.inc
 *
 * Provides:
 * 1. pf anchor configuration generation and filter reload via pfctl.
 * 2. Background daemon process supervisor.
 * 3. Health check status callback for pfSense dashboard widget.
 */

require_once("config.inc");
require_once("functions.inc");
require_once("filter.inc");
require_once("service-utils.inc");

define('FOCUS_DNS_CONFIG_PATH', '/usr/local/etc/focus_dns.conf');
define('FOCUS_DNS_PF_ANCHOR_FILE', '/etc/pf.anchors/focus_dns');
define('FOCUS_DNS_DAEMON_BIN', '/usr/local/sbin/focus-router-daemon');

/**
 * Resynchronizes FocusDNS package configuration with system PF rules and daemon.
 */
function focus_dns_sync_config() {
    global $config;

    $pkg_config = $config['installedpackages']['focus_dns']['config'][0] ?? [];
    $enabled = ($pkg_config['enable'] === 'yes' || $pkg_config['enable'] === 'on');
    $profile_id = $pkg_config['profile_id'] ?? 'profile_home_primary';
    $interfaces = $pkg_config['interfaces'] ?? ['lan'];
    $block_doh = ($pkg_config['block_rogue_doh'] ?? 'on') === 'on';

    if (!$enabled) {
        log_error("[FocusDNS] Service disabled. Flushing PF anchors and stopping daemon.");
        focus_dns_flush_pf_anchor();
        stop_service("focus_dns");
        return;
    }

    log_error("[FocusDNS] Reconfiguring PF anchor rules and restarting daemon (Profile: {$profile_id})...");

    // 1. Generate FreeBSD Packet Filter anchor file
    $if_list = implode(' ', (array)$interfaces);
    $pf_content = <<<EOT
# FocusDNS pfSense Anchor Rules
rdr pass on { {$if_list} } proto { udp tcp } from any to ! 127.0.0.1 port 53 -> 127.0.0.1 port 5353 tag "FocusDNS_DNS_Redirect"
pass in quick on lo0 proto { udp tcp } from any to 127.0.0.1 port 5353 tag "FocusDNS_Local_Proxy"

EOT;

    if ($block_doh) {
        $pf_content .= <<<EOT
# Block direct rogue DoH resolver IPs
block drop out log quick proto tcp to { 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 9.9.9.9 149.112.112.112 208.67.222.222 208.67.220.220 } port 443 label "FocusDNS: Drop Rogue DoH"
block drop out log quick proto tcp to any port 853 label "FocusDNS: Drop Rogue DoT"

EOT;
    }

    file_put_contents(FOCUS_DNS_PF_ANCHOR_FILE, $pf_content);

    // 2. Load anchor into live pf engine
    mwexec("/sbin/pfctl -a focus_dns -f " . escapeshellarg(FOCUS_DNS_PF_ANCHOR_FILE));

    // 3. Restart background router stub daemon
    restart_service("focus_dns");
}

/**
 * Flushes the pfSense focus_dns anchor table.
 */
function focus_dns_flush_pf_anchor() {
    if (file_exists(FOCUS_DNS_PF_ANCHOR_FILE)) {
        unlink(FOCUS_DNS_PF_ANCHOR_FILE);
    }
    mwexec("/sbin/pfctl -a focus_dns -F all");
}

/**
 * Checks whether the FocusDNS router daemon process is active.
 */
function focus_dns_check_status() {
    return is_service_running("focus_dns");
}
?>
