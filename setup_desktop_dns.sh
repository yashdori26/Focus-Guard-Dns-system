#!/usr/bin/env bash
# FocusDNS Desktop & System-Wide DNS Setup Helper
# Configures Linux system DNS and browser Secure DNS (DoH) to route through FocusDNS

set -e

FOCUS_DNS_HTTP_PORT=8080
FOCUS_DNS_UDP_PORT=5354
PROFILE_ID="dce22d"

echo "============================================================"
echo "          FOCUS-DNS DESKTOP & BROWSER SETUP HELPER          "
echo "============================================================"

# 1. Configure Browser DoH for Brave and Google Chrome Flatpak profiles
configure_browser_preferences() {
    local BROWSER_NAME="$1"
    local PREF_FILE="$2"
    
    if [ -f "$PREF_FILE" ]; then
        echo "🔧 Configuring $BROWSER_NAME with Strict FocusDNS DoH..."
        python3 -c "
import json
path = '$PREF_FILE'
try:
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    data['dns_over_https'] = {
        'mode': 'secure',
        'templates': 'https://127.0.0.1:8443/dns-query/$PROFILE_ID'
    }
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f)
    print('  ✓ $BROWSER_NAME Preferences updated successfully.')
except Exception as e:
    print('  ⚠️ Error updating $BROWSER_NAME:', e)
"
    fi
}

BRAVE_PREFS="$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/Default/Preferences"
CHROME_PREFS="$HOME/.var/app/com.google.Chrome/config/google-chrome/Default/Preferences"

# 0. Trust FocusDNS Root CA in user & Flatpak NSS databases
install_nss_cert() {
    local TARGET_DIR="$1"
    if [ -d "$TARGET_DIR" ]; then
        if certutil -d sql:"$TARGET_DIR" -L 2>/dev/null | grep -q "FocusDNS Root CA"; then
            echo "  ✓ Certificate already trusted in $TARGET_DIR"
            return 0
        fi
        echo "" | certutil -d sql:"$TARGET_DIR" -A -t "CT,C,C" -n "FocusDNS Root CA" -i "$(dirname "$0")/server/certs/focus_dns.crt" 2>/dev/null || true
        echo "  ✓ Certificate trusted in $TARGET_DIR"
    fi
}

echo "📜 Installing FocusDNS Local Authority into trust databases..."
install_nss_cert "$HOME/.pki/nssdb"
install_nss_cert "$HOME/.var/app/com.brave.Browser/.pki/nssdb"
install_nss_cert "$HOME/.var/app/com.google.Chrome/.pki/nssdb"

configure_browser_preferences "Brave Browser" "$BRAVE_PREFS"
configure_browser_preferences "Google Chrome" "$CHROME_PREFS"

# 2. System-wide DNS (requires root / sudo)
if [ "$(id -u)" -eq 0 ]; then
    echo "🛡️  Configuring Linux System-Wide Port 53 Redirection..."
    iptables -t nat -C OUTPUT -p udp -d 127.0.0.1 --dport 53 -j REDIRECT --to-ports $FOCUS_DNS_UDP_PORT 2>/dev/null || \
    iptables -t nat -A OUTPUT -p udp -d 127.0.0.1 --dport 53 -j REDIRECT --to-ports $FOCUS_DNS_UDP_PORT
    echo "  ✓ Port 53 redirected to FocusDNS port $FOCUS_DNS_UDP_PORT"
else
    echo ""
    echo "💡 To enforce system-wide DNS for non-browser apps, run:"
    echo "   sudo iptables -t nat -A OUTPUT -p udp -d 127.0.0.1 --dport 53 -j REDIRECT --to-ports $FOCUS_DNS_UDP_PORT"
fi

echo ""
echo "🎉 FocusDNS is ready! Restart Brave or Chrome to activate."
