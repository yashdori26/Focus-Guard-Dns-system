#!/usr/bin/env bash
# FocusDNS Linux System-Wide Setup Script
# Configures System-Wide Encrypted DNS (DoT / DoH), Trust Store & Root CA
# Profile: Yash (dce22d)

set -e

SERVER_IP="${1:-192.168.0.102}"
PROFILE_ID="${2:-dce22d}"
HTTPS_PORT="${3:-8443}"
DOT_PORT="${4:-8853}"

echo "============================================================"
echo "        FOCUS-DNS SYSTEM-WIDE PROTECTION SETUP (LINUX)      "
echo "============================================================"
echo "Shield Profile: Yash ($PROFILE_ID)"
echo "DNS Server:     $SERVER_IP (DoH: $HTTPS_PORT, DoT: $DOT_PORT)"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_PATH="$SCRIPT_DIR/focus_dns.crt"

# 1. Check Root
if [ "$(id -u)" -ne 0 ]; then
    echo "⚠️ This script requires sudo / root privileges to configure system trust & DNS."
    echo "Please run: sudo bash $0"
    exit 1
fi

# 2. Install Root CA into system trust store
echo "📜 [Step 1/3] Installing FocusDNS Root CA into system trust..."
if [ -d /usr/local/share/ca-certificates ]; then
    # Debian / Ubuntu
    cp "$CERT_PATH" /usr/local/share/ca-certificates/focus_dns.crt
    update-ca-certificates >/dev/null 2>&1
    echo "  ✓ Installed in /usr/local/share/ca-certificates/"
elif [ -d /etc/ca-certificates/trust-source/anchors ]; then
    # Arch Linux
    cp "$CERT_PATH" /etc/ca-certificates/trust-source/anchors/focus_dns.crt
    trust extract-compat >/dev/null 2>&1
    echo "  ✓ Installed in /etc/ca-certificates/trust-source/anchors/"
elif [ -d /etc/pki/ca-trust/source/anchors ]; then
    # Fedora / RHEL / CentOS
    cp "$CERT_PATH" /etc/pki/ca-trust/source/anchors/focus_dns.crt
    update-ca-trust extract >/dev/null 2>&1
    echo "  ✓ Installed in /etc/pki/ca-trust/source/anchors/"
fi

# 3. Configure systemd-resolved (if available)
echo "🛡️  [Step 2/3] Configuring system-wide encrypted DNS via systemd-resolved..."
if systemctl is-active systemd-resolved >/dev/null 2>&1 || [ -d /etc/systemd/resolved.conf.d ]; then
    mkdir -p /etc/systemd/resolved.conf.d
    cat <<EOF > /etc/systemd/resolved.conf.d/focus_dns.conf
[Resolve]
DNS=$SERVER_IP#FocusDNS
FallbackDNS=1.1.1.1#cloudflare-dns.com 8.8.8.8#dns.google
DNSOverTLS=opportunistic
EOF
    systemctl restart systemd-resolved 2>/dev/null || true
    echo "  ✓ systemd-resolved configured with FocusDNS and automatic Cloudflare fallback."
else
    echo "  ℹ️ systemd-resolved not running. Updating /etc/resolv.conf..."
    if ! grep -q "$SERVER_IP" /etc/resolv.conf; then
        echo -e "nameserver $SERVER_IP\nnameserver 1.1.1.1\n$(cat /etc/resolv.conf)" > /etc/resolv.conf
    fi
    echo "  ✓ /etc/resolv.conf updated with primary FocusDNS and fallback 1.1.1.1."
fi

# 4. Configure Browser policies for Linux (Chrome, Brave)
echo "🌐 [Step 3/3] Enforcing Secure DNS on Chrome & Brave..."
DOH_URL="https://$SERVER_IP:$HTTPS_PORT/dns-query/$PROFILE_ID"

for POLICY_DIR in /etc/opt/chrome/policies/managed /etc/brave/policies/managed; do
    mkdir -p "$POLICY_DIR"
    cat <<EOF > "$POLICY_DIR/focus_dns.json"
{
  "DnsOverHttpsMode": "secure",
  "DnsOverHttpsTemplates": "$DOH_URL"
}
EOF
    echo "  ✓ Policy created in $POLICY_DIR/focus_dns.json"
done

echo ""
echo "============================================================"
echo "🎉 FOCUS-DNS PROTECTION IS NOW ACTIVE SYSTEM-WIDE ON LINUX!"
echo "============================================================"
echo "• Adult, regional, and gambling domains are blocked."
echo "• Normal internet works at full speed with Cloudflare fallback."
echo "• To restore default settings anytime, run 'sudo bash restore_linux.sh'."
echo ""
