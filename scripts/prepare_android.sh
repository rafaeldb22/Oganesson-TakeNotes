#!/usr/bin/env bash
# Generates the android/ folder with `flutter create` (lib/ and pubspec.yaml are
# left untouched), copies the custom Android files on top (widgets, manifest),
# enables core library desugaring and generates the app icon.
# Usage: bash scripts/prepare_android.sh
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --org com.rafa --project-name notas --platforms=android .
rm -rf test

cp -r platform/android/app/. android/app/
python3 scripts/patch_android.py

flutter pub get
dart run flutter_launcher_icons -f icons-android.yaml
