# FocusDNS (2) - Sovereign On-Device Focus & Privacy Shield

[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20(Profile)%20%7C%20Web-blue.svg)](https://flutter.dev)
[![Architecture](https://img.shields.io/badge/Architecture-100%25%20On--Device%20%7C%20Zero--Cloud-brightgreen.svg)]()
[![Design System](https://img.shields.io/badge/Design-Wabi--Sabi%20(Stone%20Paper%20%2F%20Charcoal)-orange.svg)]()
[![License](https://img.shields.io/badge/License-MIT-purple.svg)]()

> **FocusDNS** is a high-performance, sovereign digital focus and content-filtering system. It combines a local DNS-only VPN tunnel, system-level accessibility inspection, and anti-uninstall device administration into an elegant, tactile **Wabi-Sabi** interface.
> 
> **Zero Cloud Dependency:** Every DNS query resolution, category lookup, query log, and strict timer happens **100% on your device** inside local SQLite. Your traffic never leaves your hardware.

---

## 🏛️ System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       FLUTTER PRESENTATION LAYER                            │
│  • Wabi-Sabi Theme (Stone Paper #F7F6F2 / Charcoal Dark #121214)            │
│  • Typography: Fraunces (Headlines) • Inter (UI) • JetBrains Mono (Metrics) │
│  • State Management: Flutter Riverpod 2.x • SharedPreferences Persistence    │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │ MethodChannels
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    NATIVE KOTLIN CORE ENGINE (Android)                      │
│                                                                             │
│  ┌───────────────────────┐  ┌───────────────────────┐  ┌─────────────────┐  │
│  │  FocusDnsVpnService   │  │FocusAccessibilitySvc  │  │ FocusDeviceAdmin│  │
│  │  • TUN Virtual Bind   │  │• Browser URL Guard    │  │ • Anti-Uninstall│  │
│  │  • DoH/DoT Trap Routes│  │• App Package Block    │  │ • Strict Mode   │  │
│  │  • SafeSearch VIPs    │  │• Reels/Shorts Killer  │  │   Enforcement   │  │
│  │  • Upstream Sockets   │  │• Anti-VPN Bypass      │  │                 │  │
│  └───────────┬───────────┘  └───────────┬───────────┘  └────────┬────────┘  │
│              │                          │                       │           │
│              ▼                          ▼                       ▼           │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                   RulesStore & LocalDb (SQLite)                       │  │
│  │  • 45,000+ Porn, Gambling, Social Media & Tracker Domains             │  │
│  │  • Keyword Heuristics & RegEx Suffix Matcher                          │  │
│  │  • Query Audit Logs & Aggregated Telemetry                            │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## ✨ Key Capabilities & Features

### 1. Local DNS-Only VPN Tunnel
* **Local Virtual Bind**: Establishes local virtual DNS at `10.111.222.1` / `10.111.222.2` (IPv4) and `fd00::1` / `fd00::2` (IPv6).
* **Anti-Bypass Traps**: Injects route traps for known public DNS resolvers (`1.1.1.1`, `8.8.8.8`, `9.9.9.9`, `94.140.14.14`, etc.) into the tunnel to capture hardcoded browser DoH queries.
* **TCP Reset on Leak Ports**: Actively issues TCP RST on ports 53, 443, and 853 for prohibited hostnames to prevent browser fallback bypass.
* **SafeSearch VIP Redirection**: Rewrites search engine queries (Google, Bing, DuckDuckGo) directly to strict SafeSearch VIP addresses at the socket level.

### 2. Multi-Layer Security Under External VPNs
* **Browser Address Bar URL Inspection**:
  * Even when another VPN takes over the Android `VpnService` network tunnel, `FocusAccessibilityService` monitors foreground browser address bars (Chrome, Brave, Samsung Internet, Firefox, Edge, Opera, DuckDuckGo, Kiwi, etc.).
  * If a prohibited domain (adult, gambling, social, custom denylist) is detected in the address bar, FocusDNS immediately executes `GLOBAL_ACTION_HOME` and displays `BlockedActivity` with the exact block reason.
* **Independent App Interception**: Distracting packages in `Rules.packages` are terminated instantly without requiring the VPN service to be running.
* **Anti-VPN Bypass Trap**: Intercepts third-party VPN apps or circumvention attempts while Focus Shield is active.

### 3. Background Resilience & State Persistence
* **Task Removal Protection (`onTaskRemoved`)**:
  * If Focus Shield, Strict Mode, or protection is active and the user swipes the app away from Recents, the service keeps running in the foreground with an ongoing notification and revival alarms.
  * If no modes are active, the app cleanly releases background resources without battery drain.
* **Zero Settings Reset**:
  * Preserves the active tab, sub-tab, user profile name, custom allowlist/denylist, and toggle configurations across restarts.

### 4. Decluttered "More" Menu
* Replaced complex, nested menus with tactile, grouped cards featuring direct **inline toggle switches** and plain English 1-line descriptions:
  * **Network & Filtering**: Threat Shield, SafeSearch, Ad & Tracker Blocker, Anti-VPN Bypass.
  * **Distraction & Feed Killers**: YouTube Shorts Interceptor, Instagram Reels Blocker, Accessibility App Blocker.
  * **Focus & Device Security**: Strict Mode Lock, Anti-Uninstall Device Admin, Dark Theme, Battery Optimization Immunity.
  * **Data & System Tools**: Custom Domain Rules, Clear Query Logs, Re-run Setup Walkthrough.

### 5. Cross-Platform iPhone (iOS) & Web Support
* **Flutter Web PWA**: Full-screen standalone web app with "Add to Home Screen" support on Safari.
* **Apple Encrypted DNS Profile (`.mobileconfig`)**: Native system-wide DNS-over-HTTPS profile for iOS Settings (zero app installation needed on iPhone).

---

## 🚀 Getting Started

### Prerequisites
* [Flutter SDK](https://flutter.dev) (v3.24+ recommended)
* [Android SDK](https://developer.android.com/studio) with Command-Line Tools & Platform 34
* JDK 17+

### Running the Android App
```bash
# 1. Fetch dependencies
flutter pub get

# 2. Build debug APK
flutter build apk --debug

# 3. Install on connected Android device / emulator
flutter install
# Or run live:
flutter run
```

### Running the Web Version for iPhone
```bash
# 1. Build the web app
flutter build web

# 2. Serve the build locally
python3 -m http.server 8080 --directory build/web

# 3. Access on your iPhone (same Wi-Fi):
# Open Safari -> http://<YOUR_LOCAL_IP>:8080 -> Share -> "Add to Home Screen"
```

### Installing the Apple iOS DNS Profile on iPhone
1. Open Safari on your iPhone and navigate to:
   ```
   http://<YOUR_LOCAL_IP>:8080/focusdns.mobileconfig
   ```
2. Tap **Allow** to download the profile.
3. Open **Settings → Profile Downloaded → Install**.
4. Confirm in **Settings → General → VPN, DNS & Device Management → DNS** that **FocusDNS iOS Shield** is active.

---

## 📁 Repository Directory Map

```
focus-dns (2)/
├── android/
│   ├── app/src/main/
│   │   ├── AndroidManifest.xml          # Permissions, receivers & services
│   │   ├── assets/blocklists/           # Bundled blocklists (porn, gambling, social)
│   │   └── kotlin/com/focusdns/focus_dns/
│   │       ├── BlockedActivity.kt       # Tactile block warning screen
│   │       ├── BootReceiver.kt          # Automatic revival on device boot
│   │       ├── Bridge.kt                # Flutter <-> Native MethodChannel bridge
│   │       ├── DnsPacket.kt / DnsStats  # Packet parser & memory telemetry
│   │       ├── FocusAccessibilityService# Browser URL inspector & app killer
│   │       ├── FocusDeviceAdminReceiver # Android Enterprise anti-uninstall lock
│   │       ├── FocusDnsVpnService.kt    # Local VPN TUN DNS-only engine
│   │       ├── LocalDb.kt               # Local SQLite database (logs, rules, KV)
│   │       ├── MainActivity.kt          # Platform channel handlers
│   │       └── Rules.kt                 # In-memory rule caches & heuristics
├── lib/
│   ├── backend/                         # Native service managers (VPN, Blocker, MDM)
│   ├── frontend/
│   │   ├── home_screen.dart             # Primary tactile tab controller
│   │   ├── more_screen.dart             # Decluttered options menu with inline toggles
│   │   ├── phone_auth_sheet.dart        # Elevated phone SMS auth bottom sheet
│   │   ├── screens/onboarding/          # 3-Step sovereign setup walkthrough
│   │   ├── tabs/                        # Allowlist, Denylist, Deep Focus, Logs tabs
│   │   └── theme/wabi_sabi_theme.dart   # Stone Paper & Charcoal Dark palettes
│   ├── models/                          # Data models & enum definitions
│   ├── services/                        # AppStorageService & AuthStorageService
│   └── state_management/                # Riverpod Notifiers & state providers
├── web/                                 # Flutter Web & PWA assets
├── pubspec.yaml                         # Flutter dependencies & metadata
└── README.md                            # Complete technical documentation
```

---

## 🔒 Security & Privacy Guarantees

* **Zero Telemetry**: No third-party analytics (Google Analytics, Firebase, Mixpanel, Sentry) are bundled.
* **100% Sovereign**: All domain decisions and logs are stored in your device's private SQLite file.
* **Anti-Tamper**: When Strict Mode is active, disabling filters or turning off features is mathematically locked until the timer expires.
