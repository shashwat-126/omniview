#!/usr/bin/env bash
# Small APKs WITHOUT the LibreOffice engine (PDF, images, XLSX grid, CSV, text, notebooks, ZIP still work;
# DOCX/PPTX show extracted text; legacy/ODF Office files are unsupported).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
cp tool/lite_overrides.yaml pubspec_overrides.yaml
trap 'rm -f pubspec_overrides.yaml' EXIT
flutter clean
flutter pub get
flutter build apk --release --split-per-abi --split-debug-info=build/symbols
for f in build/app/outputs/flutter-apk/app-*-release.apk; do
  abi=$(basename "$f" | sed 's/app-\(.*\)-release.apk/\1/')
  cp "$f" "dist/omniview-lite-$abi.apk"
done
ls -lh dist
