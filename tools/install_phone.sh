#!/usr/bin/env bash
# ==============================================================================
# FocusDNS Direct ADB USB / Wireless Auto-Installer & Real-Time Log Streamer
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RELEASE_APK="${PROJECT_ROOT}/build/app/outputs/flutter-apk/app-release.apk"
DEBUG_APK="${PROJECT_ROOT}/build/app/outputs/flutter-apk/app-debug.apk"
APK_TO_INSTALL=""

if [[ -f "${RELEASE_APK}" ]]; then
  APK_TO_INSTALL="${RELEASE_APK}"
elif [[ -f "${DEBUG_APK}" ]]; then
  APK_TO_INSTALL="${DEBUG_APK}"
else
  echo "❌ Error: No built APK found in build/app/outputs/flutter-apk/"
  echo "Please build the APK first with 'flutter build apk --release'"
  exit 1
fi

APK_SIZE_MB=$(du -m "${APK_TO_INSTALL}" | cut -f1)

echo "=========================================================="
echo "⚡ FocusDNS Native Phone Installer & Diagnostics"
echo "=========================================================="
echo "📦 Target APK : ${APK_TO_INSTALL}"
echo "📏 Binary Size: ${APK_SIZE_MB} MB"
echo ""

# 1. Check if adb command exists
if ! command -v adb &> /dev/null; then
  echo "❌ Error: 'adb' command is not found in your system PATH."
  echo "Please ensure Android Platform Tools is installed."
  exit 1
fi

# 2. Check for attached devices
DEVICES=$(adb devices | awk 'NR>1 && $2=="device" {print $1}')

if [[ -z "${DEVICES}" ]]; then
  echo "⚠️ No Android device currently detected via ADB."
  echo ""
  echo "To connect your phone, choose one of two simple methods:"
  echo "--------------------------------------------------------"
  echo "Method A: USB Cable"
  echo "  1. On your phone: Go to Settings -> About Phone -> Tap 'Build Number' 7 times."
  echo "  2. Go to Developer Options -> Turn ON 'USB Debugging'."
  echo "  3. Connect phone to PC using a USB cable."
  echo "  4. Tap 'Allow USB Debugging' on phone screen."
  echo "  5. Re-run this script: ./tools/install_phone.sh"
  echo ""
  echo "Method B: Wireless ADB (Wi-Fi)"
  echo "  1. Connect phone and PC to the same Wi-Fi network."
  echo "  2. In Developer Options -> Turn ON 'Wireless Debugging'."
  echo "  3. Note IP address and Port (e.g., 192.168.0.50:5555)."
  echo "  4. Run: adb connect <phone-ip>:<port>"
  echo "  5. Re-run this script: ./tools/install_phone.sh"
  echo "--------------------------------------------------------"
  exit 0
fi

DEVICE_COUNT=$(echo "${DEVICES}" | wc -l)
echo "✅ Detected ${DEVICE_COUNT} connected device(s):"
for dev in ${DEVICES}; do
  MODEL=$(adb -s "${dev}" shell getprop ro.product.model 2>/dev/null || echo "Android Device")
  ANDROID_VER=$(adb -s "${dev}" shell getprop ro.build.version.release 2>/dev/null || echo "Unknown")
  echo "   📱 [${dev}] ${MODEL} (Android ${ANDROID_VER})"
done
echo ""

TARGET_DEV=$(echo "${DEVICES}" | head -n1)
echo "🚀 Installing APK onto primary device: ${TARGET_DEV}..."
adb -s "${TARGET_DEV}" install -r -d "${APK_TO_INSTALL}"

echo ""
echo "🔍 Verifying installation on ${TARGET_DEV}..."
if adb -s "${TARGET_DEV}" shell pm list packages | grep -q "com.focusdns.app"; then
  echo "🎉 Success: com.focusdns.app is successfully installed and verified!"
else
  echo "❌ Installation verification failed. Package com.focusdns.app not found."
  exit 1
fi

echo ""
echo "Granting notification permissions..."
adb -s "${TARGET_DEV}" shell pm grant com.focusdns.app android.permission.POST_NOTIFICATIONS 2>/dev/null || true

echo ""
echo "=========================================================="
echo "🎯 Launching FocusDNS on device..."
adb -s "${TARGET_DEV}" shell monkey -p com.focusdns.app -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1

echo ""
echo "📡 Streaming live diagnostics logcat (Press Ctrl+C to exit)..."
echo "Filtering for: FocusAccessibility, FocusDnsVpn, SurgicalInspector"
echo "=========================================================="
adb -s "${TARGET_DEV}" logcat -v time -s FocusAccessibility:V FocusDnsVpn:V SurgicalInspector:V SurgicalChannel:V
