#!/usr/bin/env bash
# FocusDNS Linux Restore Script - Restores default DNS & browser policies

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "⚠️ This script requires sudo / root privileges to restore settings."
    echo "Please run: sudo bash $0"
    exit 1
fi

echo "============================================================"
echo "          FOCUS-DNS RESTORE DEFAULT LINUX SETTINGS          "
echo "============================================================"

# 1. Remove resolved config
if [ -f /etc/systemd/resolved.conf.d/focus_dns.conf ]; then
    rm -f /etc/systemd/resolved.conf.d/focus_dns.conf
    systemctl restart systemd-resolved 2>/dev/null || true
    echo "  ✓ Removed systemd-resolved focus_dns.conf"
fi

# 2. Remove browser policies
rm -f /etc/opt/chrome/policies/managed/focus_dns.json
rm -f /etc/brave/policies/managed/focus_dns.json
echo "  ✓ Removed browser enforcement policies"

# 3. Remove installed CA
if [ -f /usr/local/share/ca-certificates/focus_dns.crt ]; then
    rm -f /usr/local/share/ca-certificates/focus_dns.crt
    update-ca-certificates >/dev/null 2>&1 || true
    echo "  ✓ Removed CA certificate"
fi

echo ""
echo "Default Linux DNS and browser policies restored successfully."
