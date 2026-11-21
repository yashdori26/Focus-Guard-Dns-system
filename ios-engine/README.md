# FocusDNS iPhone Engine (`ios-engine`)

Production-grade, zero-countdown, local-first iOS 16.0+ enforcement engine for FocusDNS written in Swift 5.9+.

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
| SessionStateMachine    |<==============================| DeviceActivityCenter   |
| Engine                 |  Catch-up eval & monitor      | (Schedule intervals    |
| - Pure isBlocked()     |  extensions                   |  >= 15m constraint)    |
| - Monotonic anchor     |                               +------------------------+
| - Option B Lockout     |                                           |
+-----------+------------+                                           v
            |                                    +------------------------+
            +----------------------------+       | DeviceActivityMonitor  |
            |                            |       | Extension              |
            v                            v       +------------------------+
+------------------------+   +------------------------+              |
| Apple Encrypted DNS    |   | ManagedSettingsStore   |              v
| Profile (.mobileconfig)|   | - Application tokens   |  +------------------------+
| - DoH RFC 8484         |   | - denyAppRemoval=true  |  | ShieldActionService    |
| - Passcode lock '2026' |   +------------------------+  | - Option B Zero Bypass |
+-----------+------------+               |               +------------------------+
            |                            v                           |
            v                +------------------------+              v
+------------------------+   | AppGroupSessionStore   |<-------------+
| DomainMatcher          |   | (group.com.focusdns.app|
| - Canonical Punycode   |   |  shared container)     |
| - Wildcard matching    |   +------------------------+
+------------------------+
```

## Key Components

1. **`SessionStateMachineEngine`**:
   - Pure evaluation function `isBlocked(target, wallNowMs, monoNowMs)`.
   - Precomputes absolute timeline intervals (`[PhaseInterval]`) anchored to both wall-clock epoch and system monotonic uptime (`ProcessInfo.processInfo.systemUptime`).
   - Anti-tamper clock jump detection: flags manipulation if monotonic elapsed differs from wall clock by > 15–60 seconds.
   - Enforces **Option B (Absolute Ironclad Lockout)**: strictly rejects pause/stop/abort commands during active strict focus sessions (`ERR_PAUSE_NOT_ALLOWED`, `ERR_STRICT_LOCKOUT_ACTIVE`).

2. **`FamilyControlsCoordinator`**:
   - Manages Apple FamilyControls authorization (`AuthorizationCenter.shared.requestAuthorization(for: .individual)`).
   - Verifies developer entitlement status (`.approved`, `.denied`, `.notDetermined`).

3. **`ManagedSettingsEngine`**:
   - Manages OS-level shield policies using Apple's `ManagedSettings` framework.
   - Shields application tokens, web domain tokens, and category tokens.
   - Toggles `store.application.denyAppRemoval = true` during strict focus sessions to prevent app uninstallation.

4. **`DeviceActivityScheduler`**:
   - Interfaces with `DeviceActivityCenter`.
   - Specifically respects Apple's **15-minute (900-second) minimum schedule interval constraint**.
   - Focus blocks $\ge 15$m are monitored natively via `DeviceActivitySchedule`; shorter micro-breaks (e.g. 5m Pomodoro) synchronize state via the shared App Group container.

5. **`DeviceActivityMonitorExtension` & `ShieldActionService`**:
   - Standalone extension services invoked by iOS outside the main app process.
   - `ShieldActionService` strictly returns `.close` for any user interaction during active strict sessions, enforcing zero-bypass protection.

6. **`DnsProfileGenerator` & `NetworkFreezeEngine`**:
   - Generates Apple `.mobileconfig` profiles with `com.apple.dnsSettings.managed` DoH endpoints and removal password locking (`<key>HasRemovalPasscode</key><true/>`).
   - Implements Network Freeze policy for distracting apps (Instagram, YouTube, TikTok, Reddit), routing lookups to `0.0.0.0` or NXDOMAIN to halt new feeds while preserving cached items.

7. **`DomainMatcher` & `Ed25519RulePackVerifier`**:
   - High-throughput in-memory domain matcher with Punycode normalization and wildcard subdomain matching (`*.instagram.com`, `*.googlevideo.com`).
   - Ed25519 signature verification using Apple's `CryptoKit` with emergency kill-switch capability.

8. **`AppGroupSessionStore`**:
   - Inter-process shared container persistence across main app and extensions via `group.com.focusdns.app`.

## Automated Verification

Run verification suite:
```bash
python3 ios-engine/verify_ios_engine.py
```
Validates structural integrity, balanced syntax across all Swift components, Option B Ironclad Lockout guarantees, and passes all 10 shared state machine test vectors (42 assertions).
