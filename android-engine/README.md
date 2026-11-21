# FocusDNS Android Engine (`:android-engine`)

Production-grade, zero-countdown, local-first Android enforcement engine for FocusDNS.

## Architecture Overview

```
                      +-----------------------------------+
                      |   Flutter Platform Channel Bridge |
                      +-----------------+-----------------+
                                        |
           +----------------------------+----------------------------+
           |                                                         |
           v                                                         v
+------------------------+                               +------------------------+
| SessionStateMachine    |<==============================| ExactAlarmManager      |
| Engine                 |  Catch-up eval & wake alarms  | (setExactAndAllowWhile |
| - Pure isBlocked()     |                               |  Idle & BootWatchdog)  |
| - Monotonic anchor     |                               +------------------------+
| - Option B Lockout     |
+-----------+------------+
            |
            +----------------------------+
            |                            |
            v                            v
+------------------------+   +------------------------+
| VpnEngine & Tun        |   | AccessibilityEngine    |
| Interceptor            |   | - Reel/Shorts ViewTree |
| - 10.254.1.2 tun       |   | - Break sweep (Home)   |
| - Port 53 NXDOMAIN     |   +------------------------+
| - DoH RFC 8484 uplink  |               |
+-----------+------------+               v
            |                +------------------------+
            v                | FocusDeviceAdminGuard  |
+------------------------+   | - Anti-uninstall lock  |
| RulesEngine (Ed25519)  |   +------------------------+
| - Canonical IDN/Puny   |               |
| - Exact & Wildcard     |               v
+------------------------+   +------------------------+
                             | EncryptedSessionStore  |
                             | - AES-256 GCM Journal  |
                             +------------------------+
```

## Key Components

1. **`SessionStateMachineEngine`**:
   - Pure evaluation function `isBlocked(target, nowMs, state)`.
   - Precomputes absolute timeline intervals (`List<PhaseInterval>`) anchored to both wall-clock epoch and `SystemClock.elapsedRealtime()`.
   - Anti-tamper clock jump detection: flags manipulation if monotonic elapsed differs from wall clock by > 60 seconds.
   - Enforces **Option B (Absolute Ironclad Lockout)**: strictly rejects pause/stop/abort commands during active strict focus sessions.

2. **`VpnEngine` & `DnsTunInterceptor`**:
   - DNS-only `VpnService` establishing a TUN interface at `10.254.1.2/32` with DNS routed to `10.254.1.2`.
   - Intercepts UDP port 53 packets, parses RFC 1035 wire format.
   - Blocks denied domains instantly by synthesizing NXDOMAIN (RCODE 3).
   - Forwards allowed queries to upstream DNS-over-HTTPS (RFC 8484) endpoints.
   - Detects conflicting VPNs gracefully: pauses DNS interception without crashing, preserves shields, and broadcasts degraded state.

3. **`AccessibilityEngine`**:
   - Surgical view tree inspector targeting YouTube Shorts (`reel_recycler`, `reel_player_page_tree`) and Instagram Reels (`clips_viewer_root_view`, `clips_video_container`).
   - Non-destructive intervention: executes `GLOBAL_ACTION_BACK` upon feed detection.
   - Break sweep: invokes `GLOBAL_ACTION_HOME` to cleanly dismiss distracting apps when a scheduled break interval activates.

4. **`RulesEngine` & `SignedRulePackParser`**:
   - In-memory high-throughput domain index supporting exact matches and wildcard subdomain matching (`*.instagram.com`, `*.googlevideo.com`).
   - Normalizes domains via `java.net.IDN.toASCII()` to prevent Punycode homograph bypasses.
   - Dynamic signed rule pack parsing with Ed25519 cryptographic signature verification and emergency kill-switch capability.

5. **`ExactAlarmManager` & `BootWatchdogReceiver`**:
   - Schedules exact wakeups via `AlarmManager.setExactAndAllowWhileIdle()`.
   - Alarms act purely as wake signals; the state machine performs catch-up evaluation on every wake.
   - Re-registers active schedules upon device reboot via `BOOT_COMPLETED`.

6. **`FocusDeviceAdminReceiver`**:
   - Enforces Device Administration policies.
   - Intercepts and blocks uninstallation attempts during active strict focus sessions.

7. **`EncryptedSessionStore`**:
   - Backed by Android Jetpack Security (`EncryptedSharedPreferences`).
   - Persists session event log and latest state snapshots using hardware-backed AES-256 GCM encryption.

## Verification & Testing

Run unit tests via Gradle:
```bash
export JAVA_HOME=/home/ya5/.local/jdks/jdk-17.0.12+7
export PATH=$JAVA_HOME/bin:$PATH
cd android && ./gradlew :android-engine:test
```
All 9 unit tests cover monotonic timeline projection, catch-up evaluation, anti-tamper clock jumps, strict mode lockout rejection, Punycode canonicalization, and wildcard subdomain matching.
