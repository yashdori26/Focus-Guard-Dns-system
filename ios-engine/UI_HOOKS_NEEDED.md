# UI Hooks Needed (iPhone Engine)

In strict accordance with the project guidelines, **zero modifications** have been made to existing Flutter UI widgets, layouts, themes, copy, or navigation.

To connect the existing Flutter frontend with the new `ios-engine` backend on Apple devices, the following platform channel method calls and event streams are exposed and ready to be bound:

## 1. Method Channels (`com.focusdns.app/screen_time`)

| Method Name | Arguments | Return Type | Description |
|-------------|-----------|-------------|-------------|
| `requestAuthorization` | `None` | `Boolean` | Prompts user for Apple `FamilyControls` authorization for individual protection. |
| `isAuthorized` | `None` | `Boolean` | Returns true if `AuthorizationCenter.shared.status == .approved`. |
| `startSession` | `{ sessionId: String, mode: String, focusMinutes: Int, breakMinutes: Int, cycles: Int, strictLockout: Boolean }` | `Boolean` | Starts an iOS focus session. Schedules `DeviceActivitySchedule` and sets `ManagedSettingsStore.application.denyAppRemoval`. |
| `pauseSession` | `{ sessionId: String, pauseMinutes: Int }` | `Boolean` | Pauses session. Returns error `ERR_PAUSE_NOT_ALLOWED` if session is in Strict Lockout (Option B). |
| `resumeSession` | `{ sessionId: String }` | `Boolean` | Resumes an idle or paused non-strict session. |
| `stopSession` | `{ sessionId: String }` | `Boolean` | Aborts a session. Strictly rejected with `ERR_STRICT_LOCKOUT_ACTIVE` during active strict lockout. |
| `applyShields` | `{ endsAt: Int64, isStrict: Boolean }` | `Boolean` | Applies `ManagedSettingsStore` shields to selected apps and categories until `endsAt`. |
| `clearShields` | `None` | `Boolean` | Removes active application shields and unlocks app removal. |
| `getEngineStatus` | `None` | `Map<String, Any>` | Returns snapshot: `{ isAuthorized: Boolean, isShieldActive: Boolean, primaryState: String, activePhase: String, endsAt: Int64, remainingMs: Int64 }`. |
| `generateMobileConfig` | `{ removalPasscode: String? }` | `String` | Returns raw Apple `.mobileconfig` XML with DoH endpoint and passcode protection. |

## 2. Event Channels (`com.focusdns.app/screen_time_events`)

| Stream / Event Type | Payload | Trigger Condition |
|---------------------|---------|-------------------|
| `onPhaseTransition` | `{ sessionId: String, previousPhase: String, currentPhase: String, wallClockEpochMs: Long }` | Fired when `DeviceActivityMonitorExtension` or foreground catch-up detects a phase transition between `FOCUS` and `BREAK`. |
| `onShieldEvent` | `{ bundleId: String, action: String }` | Fired when user attempts to launch a shielded app and `ShieldActionService` intercepts it. |
| `onTamperDetected` | `{ type: String, details: String }` | Fired if user manually modifies iPhone system date/time while a strict session is running. |

## Recommended Flutter Provider Binding (Zero UI Changes)
A Flutter service adapter (e.g. `IosScreenTimePlatformAdapter`) can listen to these channels and bind to existing Riverpod/Bloc providers without any modifications to widgets, layouts, or screens.
