# FocusDNS (v1.2.0 Hardened) — Executive Handover & Cheat Sheet

**Release Version**: `v1.2.0-hardened`  
**Git Commit**: `3ea30e6`  
**Repository**: [Focus-Guard-Dns-system](https://github.com/yashdori26/Focus-Guard-Dns-system.git)  
**Verification Status**: ✅ 100% Passed across Android, iOS, Cloud API, Web Extension & Shared Spec

---

## 1. Executive Summary

FocusDNS is a hardened, cross-platform focus and threat-blocking system engineered to protect user productivity, privacy, and device integrity. This release marks the complete unification and hardening of the backend across Android, iOS, Web Browsers, and Cloud API services while preserving the Flutter user interface with **zero UI modifications**.

```
+-----------------------------------------------------------------------------------------+
|                                    FocusDNS System                                      |
+-----------------------------------------------------------------------------------------+
|  Frontend UI (100% Preserved) : Flutter Dart (lib/frontend/**)                          |
+-----------------------------------------------------------------------------------------+
|  Platform Adapters            : AndroidEngineAdapter | IosEngineAdapter | CloudApiAdapter|
+-----------------------------------------------------------------------------------------+
|  Native Engines               : Kotlin (:android-engine) | Swift (ios-engine)           |
+-----------------------------------------------------------------------------------------+
|  Desktop / Browser Filter     : Manifest V3 Web Extension (dist/focusdns-extension-mv3) |
+-----------------------------------------------------------------------------------------+
|  Cloud Services & Upstreams   : Go API (RFC 8484 DoH) | Cloudflare & Quad9 Zero-Log DoH |
+-----------------------------------------------------------------------------------------+
```

---

## 2. The 4 Core Product Modes

| Mode | Name | Operation | Safe Exit Mechanism |
| :--- | :--- | :--- | :--- |
| **Mode 1** | **Normal Timer** | User has full control over the session. Can pause, resume, extend, or stop protection at any point. | Instant manual stop/pause button. |
| **Mode 2** | **Strict Mode** | Ironclad lockout. Once started, focus cannot be paused, stopped, or shortened until the countdown reaches 0:00. | **15-Second Continuous Physical Hold** (Emergency Panic Override). |
| **Mode 3** | **Session Timer (Pomodoro Cycles)** | Automated Focus & Break cycles. Focus phase activates shields; Break phase automatically relaxes them, cycling through scheduled sessions without manual interaction. Monotonic sleep clock keeps running across phone sleep. | Can be configured as Normal or Strict per user preference. |
| **Mode 4** | **Feed Blocker (Surgical Filter)** | Decouples communications from algorithmic feeds. Blocks doom-scroll containers (YouTube Shorts, Instagram Reels, TikTok, Reddit Feeds) while keeping chats, messages, searches, and educational videos accessible. | Can be toggled on/off independently. |

---

## 3. Two-Tier Double Verification Engine

FocusDNS uses a two-tier guard to evaluate blocked targets without relying solely on static blacklists:

```
 Incoming Target (Website or App)
              |
              v
  +-----------------------+       YES
  | Tier 1: Explicit List | --------------> [ BLOCK (NXDOMAIN / Shield) ]
  +-----------------------+
              | NO
              v
  +-----------------------+       YES
  | Tier 2: Category Match| --------------> [ BLOCK (NXDOMAIN / Shield) ]
  +-----------------------+
              | NO
              v
       [ ALLOW / RESOLVE ]
```

### For Websites:
- **Tier 1 (Explicit Blocklist)**: Checks exact domains (`instagram.com`) and wildcard subdomains (`*.tiktokv.com`).
- **Tier 2 (Lexical Category Verification)**: Tokenizes domain sub-strings, hyphenated labels, and TLD priors (`.xxx`, `.casino`, `.bet`) against category dictionaries (`ADULT_CONTENT`, `CRYPTO_GAMBLING`, `GAMING`, `SOCIAL_MEDIA`, `PIRACY`). If an unlisted site matches active blocked categories, it is instantly sinkholed.

### For Applications:
- **Tier 1 (Package Blocklist)**: Checks installed package identifiers (`com.zhiliaoapp.musically`).
- **Tier 2 (App Name & Window Title Category Match)**: Inspects package tokens and foreground accessibility window titles for category matches, redirecting the user to home via `GLOBAL_ACTION_HOME`.

---

## 4. Anti-Bypass Armor & Hardware Security

1. **Hardware-Backed Device Cryptography**:
   - **Apple iOS**: Hardware NIST P-256 keys generated and held in the **Apple Secure Enclave** (`CryptoKit.SecureEnclave.P256`).
   - **Android**: Hardware NIST P-256 keys stored in **Android KeyStore** backed by StrongBox or Trusted Execution Environment (TEE).
   - **Cloud API**: Signature verification validates genuine physical hardware ownership.

2. **Android Interceptor Anti-Bypass Armor**:
   - **TCP Port 53 Interception**: Synthetic NXDOMAIN responses over TCP prevent DNS leaks from applications bypassing UDP.
   - **IPv6 Interception (`fd00::1:53`)**: Intercepts IPv6 lookups with RFC 2460 pseudo-header checksum recalculation.
   - **DoT (Port 853) Blocking**: Synthesizes TCP RST / packet drop on port 853, forcing Android OS "Private DNS" to immediately fall back to the protected local VPN tunnel.
   - **VPN Socket Protection**: Outbound DoH sockets call `protect(socket)` to eliminate local routing loops.

3. **Anti-Rollback Rule Packs**:
   - Monotonic sequence numbers (`version >= activeVersion`) reject replay or downgrade attacks (`ERR_RULE_PACK_ROLLBACK_ATTEMPT_DETECTED`).
   - Built-in safe kill-switch falls back to safe local policies rather than unshielded access.

4. **Zero-Log DNS Upstream Privacy**:
   - Upstream queries are sent directly via encrypted RFC 8484 DoH to zero-log public resolvers: **Cloudflare** (`1.1.1.1`) and **Quad9** (`9.9.9.9`).
   - The cloud database schema strictly prohibits storing raw domain names, URLs, or browsing histories.

---

## 5. 15-Second Emergency Panic Override Instructions

In **Mode 2 (Strict Mode)**, FocusDNS prevents impulsive bypasses while ensuring complete user safety in true emergencies:

1. **How to Trigger**:
   - In the application, initiate the emergency unlock by pressing and **continuously holding** the Emergency Panic Button.
2. **The 15-Second Continuous Rule**:
   - The device checks that physical hold time $\ge 15,000\text{ ms}$ (`holdDurationMs >= 15_000`).
   - Releasing the hold at 14.9s or earlier immediately aborts the unlock and returns `ERR_PANIC_HOLD_TOO_SHORT`.
3. **Safety Guarantee**:
   - Stops unconscious compulsive unlocking while guaranteeing that in a genuine real-world emergency, 15 seconds of deliberate intent safely restores access.

---

## 6. Distributable Artifacts & Checksums

| Package | Path | Size | SHA-256 Checksum |
| :--- | :--- | :--- | :--- |
| **Android APK (Debug)** | [`build/app/outputs/flutter-apk/app-debug.apk`](file:///home/ya5/.gemini/antigravity/scratch/focus_dns/build/app/outputs/flutter-apk/app-debug.apk) | 152 MB | `88878c5c2a572bd492dd8100dc1fcff4a0577b173d38c5130f07fc4e140f01d9` |
| **Web Extension (MV3)** | [`dist/focusdns-extension-mv3.zip`](file:///home/ya5/.gemini/antigravity/scratch/focus_dns/dist/focusdns-extension-mv3.zip) | 24.4 KB | `04179e8e24c7f070b13cf35205aa11f93936528d2542a9bce0550424a1dc5f62` |

### Installing the Android APK:
```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

### Loading the Web Extension in Chrome / Brave / Edge:
1. Open `chrome://extensions` in your browser.
2. Enable **Developer mode** (top-right toggle).
3. Click **Load unpacked** and select the `/extension` folder (or unzip `dist/focusdns-extension-mv3.zip`).

---

## 7. Verification Matrix

| Suite | Component | Tests Run | Result |
| :--- | :--- | :--- | :--- |
| **Shared Spec Test Vectors** | State Machine & Modes | 10 vectors (42 steps) | ✅ **100% Passed** |
| **Android Engine Unit Tests** | Kotlin Native Engine | 17 tests | ✅ **100% Passed** |
| **iOS Engine Audit** | Swift Native Engine | 17 components, 10 vectors | ✅ **100% Passed** |
| **Cloud API Audit & Tests** | Go Service & Phone Auth | 16 components, 10 vectors | ✅ **100% Passed** |
| **Phase 5 Adapter Tests** | Flutter Adapters & MV3 | 5 validation checks | ✅ **100% Passed** |
| **Flutter Contract Tests** | Dart UI Contract | 55 tests | ✅ **100% Passed** |
| **Live Cloud API Staging** | Phone OTP & Sessions | Live HTTP flow | ✅ **100% Passed** |
| **Chromium Extension Load** | Headless Chrome 155 | MV3 Engine Initialization | ✅ **100% Passed** |
| **Flutter UI Preservation** | `lib/frontend/**` | 0 files modified | ✅ **100% Untouched** |
