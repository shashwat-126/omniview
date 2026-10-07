#!/usr/bin/env bash
# Full build WITH the LibreOffice engine, arm64 only (covers nearly all current phones).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
rm -f pubspec_overrides.yaml
flutter clean
flutter pub get
flutter build apk --release --target-platform android-arm64 --split-debug-info=build/symbols
cp build/app/outputs/flutter-apk/app-release.apk dist/omniview-full-arm64.apk
ls -lh dist
