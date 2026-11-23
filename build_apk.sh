#!/usr/bin/env bash
# Builds a debug APK locally. Needs Flutter 3.16+ and an Android toolchain
# (Android Studio, or the command-line SDK + JDK 17) on PATH.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is not on PATH. Install it first: https://docs.flutter.dev/get-started/install"
  exit 1
fi

echo "==> Flutter $(flutter --version | head -1)"
echo "==> Generating the Android host project"
cp pubspec.yaml pubspec.original.yaml
flutter create --org com.lumen --project-name lumen --platforms=android .
cp pubspec.original.yaml pubspec.yaml
rm pubspec.original.yaml

echo "==> Installing packages"
flutter pub get

echo "==> Analyzing (report only, does not stop the build)"
flutter analyze || true

echo "==> Building debug APK"
flutter build apk --debug

APK="build/app/outputs/flutter-apk/app-debug.apk"
if [ -f "$APK" ]; then
  cp "$APK" ./lumen-debug.apk
  echo ""
  echo "Done: $(pwd)/lumen-debug.apk  ($(du -h ./lumen-debug.apk | cut -f1))"
  echo "Copy it to your phone, tap it, allow 'install unknown apps' when prompted."
else
  echo "Build finished but the APK was not found at $APK"
  exit 1
fi
