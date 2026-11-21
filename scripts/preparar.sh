#!/usr/bin/env bash
# Genera las carpetas de plataforma con `flutter create` (no sobrescribe
# lib/ ni pubspec.yaml) y copia encima los archivos propios de Android
# (widget, manifest...). Uso: bash scripts/preparar.sh [android|windows|android,windows]
set -euo pipefail
cd "$(dirname "$0")/.."

PLAT="${1:-android,windows}"

flutter create --org com.rafa --project-name notas --platforms="$PLAT" .
rm -rf test

if [[ "$PLAT" == *android* ]]; then
  cp -r plataforma/android/app/. android/app/
  python3 scripts/parchear_android.py
fi

if [[ "$PLAT" == *windows* && -f windows/runner/main.cpp ]]; then
  sed -i 's/L"notas"/L"Notas"/' windows/runner/main.cpp
fi

flutter pub get
