# FocusDNS Shared Specification (`/shared-spec`)

The `/shared-spec` module is the single source of truth for the FocusDNS cross-platform architecture. It mathematically formalizes the session lifecycle, state machine transitions, anti-tamper monotonic time tracking, JSON event sourcing schemas, signed rule pack delivery, and policy evaluation rules.

Native implementations in Kotlin (`/android-engine`), Swift (`/ios-engine`), Go (`/api`), and TypeScript (`/extension-backend`) derive directly from these schemas and specifications.

---

## Architecture & Components

```
shared-spec/
├── SPECIFICATION.md                 # Complete mathematical specification
├── README.md                        # Module overview and verification guide
├── schema/
│   ├── session_events.json          # Draft 2020-12 schema for events & snapshots
│   └── rule_pack.json               # Schema for Ed25519-signed dynamic rule packs
├── vectors/
│   └── state_machine_vectors.json   # 10 comprehensive test vectors (42 assertions)
└── verifier/
    └── verify_vectors.py            # Executable test runner validating vector conformance
```

---

## Core Specification Tenets

1. **Local-First Determinism**: Devices compute and enforce block policies locally without cloud network dependencies.
2. **Absolute Precomputed Timelines**: Timelines are precomputed as absolute epoch intervals `[startEpochMs, endEpochMs)`. No countdown timers are used for enforcement.
3. **Monotonic Anchor Defense**: Elapsed session time is governed by the monotonic clock (`elapsedRealtime` / `CLOCK_MONOTONIC`). System clock forward or backward jumps are detected as tamper events and cannot shorten strict sessions.
4. **Option B Ironclad Lockout**: Sessions in `STRICT_RUNNING` or `CYCLES_RUNNING` cannot be stopped, paused, or loosened before their precomputed end time expires.
5. **Pure Evaluation (`isBlocked`)**: A pure function evaluates targets:
   $$\text{isBlocked}(\text{target}, \text{nowMs}, \text{state}) \to \text{Decision}$$
   Returning `{ isBlocked, reason, enforcedBy, allowFallback }`.
6. **Graceful VPN Degradation**: When a third-party VPN takes over `tun0`, DNS filtering pauses and alerts the user, while Accessibility & ManagedSettings app/feed shields remain 100% active.

---

## Executing the Test Vector Verifier

To verify that the engine passes all 10 vectors and 42 assertion steps:

```bash
python3 shared-spec/verifier/verify_vectors.py
```

### Verification Result
```
=======================================================
 FocusDNS Shared Specification Test Vector Verification
 Suite: FocusDNS Shared State Machine Test Vectors (v1.0.0)
 Total Vectors to Validate: 10
=======================================================

Running [vector_01_normal_lifecycle]: Validates Normal mode start, pause, resume, and manual stop ... [PASS]
Running [vector_02_feed_only_subfeature_matrix]: Validates Feed-Only mode surgical block decisions (Shorts/Reels blocked, Messages/Watch allowed) ... [PASS]
Running [vector_03_strict_mode_ironclad_rejections]: Verifies that Pause, Stop, and Duration Reductions are strictly rejected under Option B Ironclad Lockout ... [PASS]
Running [vector_04_cycles_pomodoro_timeline_and_catchup]: Validates Cycles timeline precomputation, Focus vs Break decisions, and missed-alarm catch-up ... [PASS]
Running [vector_05_boundary_limit_validations]: Validates boundary clamps and validation failures for out-of-range configurations ... [PASS]
Running [vector_06_anti_tamper_forward_clock_drift]: Validates that a forward user clock jump does not prematurely end strict sessions ... [PASS]
Running [vector_07_anti_tamper_backward_clock_drift]: Validates that setting system clock backward does not corrupt monotonic anchor ... [PASS]
Running [vector_08_degraded_vpn_conflict]: Validates graceful degradation when another VPN takes over tun0 (Shields remain active) ... [PASS]
Running [vector_09_category_and_domain_sinkhole]: Validates exact domain, wildcard suffix, and category rules ... [PASS]
Running [vector_10_idempotent_event_replay]: Verifies that replaying duplicate events yields identical idempotent state ... [PASS]

=======================================================
 Verification Result: 10/10 Vectors Passed (42 total steps validated).
=======================================================
```
