#!/usr/bin/env bash
# One-time: generate the Android project (keeps lib/ and android/app/src/main overlay).
set -e
cp -r android/app/src/main /tmp/focusdns_main_overlay
rm -rf android
flutter create . --org com.focusdns --project-name focus_dns --platforms=android
rm -rf android/app/src/main/kotlin android/app/src/main/AndroidManifest.xml
cp -r /tmp/focusdns_main_overlay/kotlin android/app/src/main/
cp /tmp/focusdns_main_overlay/AndroidManifest.xml android/app/src/main/
mkdir -p android/app/src/main/assets android/app/src/main/res/xml android/app/src/main/res/values
cp -r /tmp/focusdns_main_overlay/assets/* android/app/src/main/assets/
cp /tmp/focusdns_main_overlay/res/xml/* android/app/src/main/res/xml/
cp /tmp/focusdns_main_overlay/res/values/focusdns_strings.xml android/app/src/main/res/values/
rm -f test/widget_test.dart
rm -rf /tmp/focusdns_main_overlay
flutter pub get
echo "Done. Run: flutter run"
