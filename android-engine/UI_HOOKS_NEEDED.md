# UI Hooks Needed (Android Engine)

In strict accordance with the project guidelines, **zero modifications** have been made to existing Flutter UI widgets, layouts, themes, copy, or navigation. 

To connect the existing Flutter frontend with the new `:android-engine` backend, the following platform channel method calls and event streams are exposed and ready to be bound:

## 1. Method Channels (`com.focusdns.engine/methods`)

| Method Name | Arguments | Return Type | Description |
|-------------|-----------|-------------|-------------|
| `startSession` | `{ sessionId: String, mode: String, focusMinutes: Int, breakMinutes: Int, cycles: Int, strictLockout: Boolean, blockedFeatures: List<String> }` | `Boolean` | Starts a focus session. Precomputes absolute timeline and schedules exact alarms. |
| `pauseSession` | `{ sessionId: String }` | `Boolean` | Requests a pause. Returns `false` or throws if session is in `STRICT_LOCKOUT` (Option B). |
| `resumeSession` | `{ sessionId: String }` | `Boolean` | Resumes an idle or paused non-strict session. |
| `stopSession` | `{ sessionId: String }` | `Boolean` | Aborts a session. Strictly rejected during active strict lockout. |
| `getEngineStatus` | `None` | `Map<String, Any>` | Returns snapshot: `{ state: String, currentPhase: String, elapsedRealtime: Long, vpnActive: Boolean, accessibilityActive: Boolean }`. |
| `applyRulePack` | `{ rawJson: String, ed25519SignatureHex: String }` | `Boolean` | Validates Ed25519 signature and atomically applies delta domain rules to `RulesEngine`. |
| `requestDeviceAdmin` | `None` | `Boolean` | Launches system intent to grant Device Administrator for anti-uninstall protection. |

## 2. Event Channels (`com.focusdns.engine/events`)

| Stream / Event Type | Payload | Trigger Condition |
|---------------------|---------|-------------------|
| `onPhaseTransition` | `{ sessionId: String, previousPhase: String, currentPhase: String, wallClockEpochMs: Long }` | Fired when exact alarm wakes the engine or catch-up evaluation transitions from `FOCUS` to `BREAK` or cycle advances. |
| `onVpnConflictDegraded` | `{ degraded: Boolean, message: String }` | Fired if a third-party VPN acquires the network tun. DNS pauses gracefully while accessibility and app shields stay 100% active. |
| `onTamperDetected` | `{ type: String, clockDeltaMs: Long, description: String }` | Fired if system monotonic elapsed clock deviates from wall clock by > 60s (manual clock rollback attempt). |
| `onAccessibilityEvent` | `{ targetApp: String, featureBlocked: String, actionTaken: String }` | Fired when surgical view tree inspector intercepts Shorts or Reels and triggers `GLOBAL_ACTION_BACK`. |

## Recommended Flutter Provider Binding (Zero UI Changes)
When ready, create a data-layer repository or state notifier (e.g., `AndroidEnginePlatformAdapter`) that subscribes to `com.focusdns.engine/events` and updates the app's existing state models without changing any widget trees.
