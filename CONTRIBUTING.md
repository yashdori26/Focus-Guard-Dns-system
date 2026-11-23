# Contributing to FocusDNS (Focus Guard DNS System)

Thank you for your interest in contributing to **FocusDNS**! We welcome contributions ranging from bug fixes, performance optimizations, and UI polish to new DNS filtering rules and platform integrations.

---

## 🚀 Quick Setup & Getting Started

### Prerequisites
- **Flutter SDK**: `>= 3.19.0` ([Install Flutter](https://docs.flutter.dev/get-started/install))
- **Android Studio** or **VS Code** with Flutter & Dart extensions
- **Android SDK**: API 34+ (Android 14) with NDK support
- **Java Development Kit (JDK)**: OpenJDK 17

### 1. Clone the Repository
```bash
git clone https://github.com/yashdori26/Focus-Guard-Dns-system.git
cd Focus-Guard-Dns-system
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Run the App
Connect an Android device or start an Android emulator, then run:
```bash
flutter run
```

---

## 🛠 How to Contribute

### If you are an Invited Collaborator:
1. Accept the invitation sent to your email or at:  
   👉 **`https://github.com/yashdori26/Focus-Guard-Dns-system/invitations`**
2. Clone directly and create your feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. Commit your changes and push directly:
   ```bash
   git push origin feature/your-feature-name
   ```
4. Open a Pull Request against `main`.

### If you are contributing via Fork (Open Source):
1. Fork the repository at:  
   👉 **`https://github.com/yashdori26/Focus-Guard-Dns-system/fork`**
2. Clone your fork locally:
   ```bash
   git clone https://github.com/<YOUR-USERNAME>/Focus-Guard-Dns-system.git
   ```
3. Create a branch, commit your work, and submit a Pull Request to `yashdori26/Focus-Guard-Dns-system:main`.

---

## 📐 Core Architecture & Guidelines

Before submitting PRs, please review these key architecture principles:

1. **100% Local-First & Zero Telemetry**:
   - FocusDNS never transmits user browsing data, logs, or personal metrics to external cloud servers.
   - All filter databases and analytics must be stored locally via Hive / SQLite / SharedPreferences.

2. **Dual-Layer Anti-Bypass Security**:
   - Primary DNS intercept runs via Android `VpnService` (`android/app/src/main/kotlin/com/focusdns/FocusVpnService.kt`).
   - Secondary inspection for third-party VPN bypass operates via `AccessibilityService` (`FocusAccessibilityService.kt`).

3. **Tactile Wabi-Sabi UI Theme**:
   - Maintain the organic, warm paper earth-tone aesthetic (`#1A1A1A` charcoal, `#F7F5EE` paper white, `#E2DEC9` warm card borders).
   - Use subtle elevation, rounded corners (16–24px), and tactile micro-interactions.

4. **Background Battery Efficiency**:
   - Background foreground service (`START_STICKY`) must only remain active when a focus mode (Deep Focus, Study, Sleep) is enabled.

---

## 🧪 Testing Your Changes

Run the Flutter test suite before opening a PR:
```bash
flutter test
```

For Android native tests:
```bash
cd android
./gradlew test
```

---

## 💬 Questions & Support
Have questions or want to discuss a new feature?
- Open an [Issue](https://github.com/yashdori26/Focus-Guard-Dns-system/issues)
- Reach out to the maintainer: **@yashdori26**
