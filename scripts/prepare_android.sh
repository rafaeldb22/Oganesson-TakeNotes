#!/usr/bin/env bash
# Generates the android/ folder with `flutter create` (lib/ and pubspec.yaml are
# left untouched), copies the custom Android files on top (widgets, manifest),
# enables core library desugaring and generates the app icon.
# Usage: bash scripts/prepare_android.sh
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --org com.rafa --project-name notas --platforms=android .
rm -f test/widget_test.dart  # only the sample test flutter create generates

cp -r platform/android/app/. android/app/
# First Python that actually runs (on Windows `python3` may be the Store alias).
if python3 -c '' 2>/dev/null; then PY=(python3)
elif python -c '' 2>/dev/null; then PY=(python)
else PY=(py -3)
fi
"${PY[@]}" scripts/patch_android.py

flutter pub get
dart run flutter_launcher_icons -f icons-android.yaml
