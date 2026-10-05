#!/usr/bin/env bash
# Copies the native bridge next to the Flutter desktop executable after
# `flutter build <platform> --release`.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
N="$ROOT/build/native"
case "${1:-}" in
  linux)
    B="$ROOT/build/linux/x64/release/bundle"
    mkdir -p "$B/lib" && cp "$N/linux/libkuputun.so" "$B/lib/"
    ;;
  windows)
    B="$ROOT/build/windows/x64/runner/Release"
    cp "$N/windows/libkuputun.dll" "$N/windows/wintun.dll" "$B/"
    ;;
  macos)
    APP="$ROOT/build/macos/Build/Products/Release/kuputun.app"
    mkdir -p "$APP/Contents/Frameworks"
    cp "$N/macos/libkuputun.dylib" "$APP/Contents/Frameworks/"
    codesign --force --sign "${MACOS_SIGN_IDENTITY:--}" "$APP/Contents/Frameworks/libkuputun.dylib"
    codesign --force --deep --sign "${MACOS_SIGN_IDENTITY:--}" --entitlements "$ROOT/macos/Runner/Release.entitlements" "$APP"
    ;;
  *) echo "usage: $0 linux|windows|macos" >&2; exit 2 ;;
esac
echo "bundled native lib for $1"
