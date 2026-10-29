"""
Asuswrt-Merlin JFFS Startup, Teardown & Anti-Tamper Watchdog Scripts.

Generates:
1. /jffs/scripts/init-start: Installs dependencies and prepares runtime environment.
2. /jffs/scripts/services-stop: Conditional shutdown hook respecting focus lock.
3. /jffs/scripts/focus_watchdog.sh: Auto-restarts crashed daemon and pings health check.
"""

from typing import Dict, Any


class AsuswrtJffsScripts:
    """Generates shell automation scripts for Asuswrt-Merlin routers."""

    @classmethod
    def generate_init_start(cls) -> str:
        """Generates /jffs/scripts/init-start."""
        return """#!/bin/sh
# FocusGuard DNS - Router Initialization Hook
logger -t "FocusDNS" "Initializing FocusDNS router engine on Asuswrt-Merlin..."

# Ensure executable permissions on all JFFS scripts
chmod a+rx /jffs/scripts/*

# Prepare runtime logging directory
mkdir -p /var/log/focus_dns
mkdir -p /var/run/focus_dns

# Start watchdog background daemon
/jffs/scripts/focus_watchdog.sh &
"""

    @classmethod
    def generate_services_stop(cls, can_uninstall: bool = True, remaining_seconds: int = 0) -> str:
        """
        Generates /jffs/scripts/services-stop.
        Strictly enforces the Conditional Uninstallation Law.
        """
        if not can_uninstall or remaining_seconds > 0:
            return f"""#!/bin/sh
# FocusGuard DNS - Conditional Shutdown Hook (LOCKED)
logger -t "FocusDNS" "ACCESS DENIED: Shutdown attempt rejected during active focus session ({remaining_seconds}s remaining)."
echo "FocusGuard router protection is currently locked. Uninstallation or deactivation is forbidden." >&2
exit 1
"""
        return """#!/bin/sh
# FocusGuard DNS - Clean Shutdown Hook (Idle Mode)
logger -t "FocusDNS" "Normal mode verified. Stopping FocusDNS router daemon and cleaning iptables..."

# Terminate watchdog
killall focus_watchdog.sh 2>/dev/null

# Clean custom iptables rules
iptables -t nat -D PREROUTING -j FOCUS_DNS_NAT 2>/dev/null
iptables -D FORWARD -j FOCUS_DNS_FWD 2>/dev/null
iptables -t nat -F FOCUS_DNS_NAT 2>/dev/null
iptables -t nat -X FOCUS_DNS_NAT 2>/dev/null
iptables -F FOCUS_DNS_FWD 2>/dev/null
iptables -X FOCUS_DNS_FWD 2>/dev/null

# Terminate stub daemon
killall focus_dns_daemon 2>/dev/null

# Restart dnsmasq to restore default WAN DNS
service restart_dnsmasq
logger -t "FocusDNS" "FocusDNS cleanly stopped."
exit 0
"""

    @classmethod
    def generate_watchdog(cls, check_interval: int = 30) -> str:
        """
        Generates /jffs/scripts/focus_watchdog.sh.
        Ensures continuous daemon operation and fail-safe recovery.
        """
        return f"""#!/bin/sh
# FocusGuard DNS - Router Anti-Tamper & Fail-Safe Watchdog
CHECK_INTERVAL={check_interval}
DAEMON_PATH="/opt/bin/focus_dns_daemon"
FAIL_COUNT=0

while true; do
    # 1. Check if daemon process is running
    if ! pidof focus_dns_daemon > /dev/null; then
        logger -t "FocusDNS-Watchdog" "Daemon process died or was terminated! Respawning..."
        $DAEMON_PATH --daemon &
    fi

    # 2. Fail-Safe Health Check: Query local stub port 5353
    if ! nslookup -port=5353 health.focusguard.local 127.0.0.1 > /dev/null 2>&1; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        logger -t "FocusDNS-Watchdog" "Local stub health check failed ($FAIL_COUNT/3)."
        if [ $FAIL_COUNT -ge 3 ]; then
            logger -t "FocusDNS-Watchdog" "FAIL-SAFE TRIGGERED: Temporarily bypassing redirection to prevent LAN outage."
            iptables -t nat -D PREROUTING -j FOCUS_DNS_NAT 2>/dev/null
        fi
    else
        if [ $FAIL_COUNT -ge 3 ]; then
            logger -t "FocusDNS-Watchdog" "FocusDNS recovered! Re-enabling NAT interception."
            iptables -t nat -I PREROUTING 1 -j FOCUS_DNS_NAT 2>/dev/null
        fi
        FAIL_COUNT=0
    fi

    sleep $CHECK_INTERVAL
done
"""
