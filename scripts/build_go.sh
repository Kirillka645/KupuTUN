#!/usr/bin/env bash
# Builds the native core bridge (Xray-core + sing-box + tun2socks).
#   scripts/build_go.sh android|ios|linux|windows|macos
# Reproducibility: -trimpath, empty build id, pinned Go toolchain (go.mod),
# committed go.sum, fixed SOURCE_DATE_EPOCH; no VCS stamping.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/go"

TAGS="${KUPUTUN_TAGS:-with_quic,with_utls,with_wireguard,with_gvisor}"
LDFLAGS="-s -w -buildid= -X github.com/xtls/xray-core/core.build=kuputun"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || echo 1700000000)}"
OUT="$ROOT/build/native"
mkdir -p "$OUT"

# First build: resolve and pin dependencies (commit the resulting go.sum).
[ -f go.sum ] || go mod tidy
export GOFLAGS="-trimpath -buildvcs=false -mod=readonly"

case "${1:-}" in
  android)
    command -v gomobile >/dev/null || go install golang.org/x/mobile/cmd/gomobile@latest
    gomobile init
    mkdir -p "$ROOT/android/app/libs"
    # 16 KB ELF page alignment: required by Google Play for Android 15+ devices
    # (NDK r28+ does it by default; the flag keeps older NDKs compliant too).
    gomobile bind -v -target=android/arm64,android/arm,android/amd64 -androidapi 24 \
      -javapkg=dev.kuputun.core -tags "$TAGS" -ldflags "$LDFLAGS -extldflags=-Wl,-z,max-page-size=16384" \
      -o "$ROOT/android/app/libs/kuputun.aar" ./bridge
    ;;
  ios)
    command -v gomobile >/dev/null || go install golang.org/x/mobile/cmd/gomobile@latest
    gomobile init
    mkdir -p "$ROOT/ios/Frameworks"
    gomobile bind -v -target=ios,iossimulator -iosversion 15 -tags "$TAGS,with_low_memory" -ldflags "$LDFLAGS" \
      -o "$ROOT/ios/Frameworks/Kuputun.xcframework" ./bridge
    ;;
  linux)
    CGO_ENABLED=1 go build -buildmode=c-shared -tags "$TAGS" -ldflags "$LDFLAGS" \
      -o "$OUT/linux/libkuputun.so" ./cmd/libkuputun
    ;;
  windows)
    # Native Windows (MSYS2/mingw gcc in PATH) or cross from Linux with mingw-w64.
    case "$(uname -s)" in
      MINGW*|MSYS*|CYGWIN*) ;;
      *) command -v x86_64-w64-mingw32-gcc >/dev/null && export CC=x86_64-w64-mingw32-gcc ;;
    esac
    CGO_ENABLED=1 GOOS=windows GOARCH=amd64 go build -buildmode=c-shared -tags "$TAGS" -ldflags "$LDFLAGS" \
      -o "$OUT/windows/libkuputun.dll" ./cmd/libkuputun
    # wintun driver DLL (signed by WireGuard LLC) for TUN mode
    if [ ! -f "$OUT/windows/wintun.dll" ]; then
      WINTUN_URL="${KUPUTUN_WINTUN_URL:-https://www.wintun.net/builds/wintun-0.14.1.zip}"
      WINTUN_SHA="07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51"
      TMPD="$(mktemp -d)"
      trap 'rm -rf "$TMPD"' EXIT
      ZIP="$TMPD/wintun.zip"
      is_windows=false
      case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) is_windows=true ;; esac

      # wintun.net resets connections fairly often, so retry and, on Windows,
      # fall back to the system HTTP stack.
      if ! curl -fsSL --retry 4 --retry-delay 2 --retry-all-errors --connect-timeout 20 \
             -o "$ZIP" "$WINTUN_URL"; then
        if [ "$is_windows" = true ]; then
          echo "curl failed; retrying with PowerShell..." >&2
          WZIP="$(cygpath -w "$ZIP")"
          powershell.exe -NoProfile -Command \
            "\$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -TimeoutSec 180 -Uri '$WINTUN_URL' -OutFile '$WZIP'"
        else
          echo "failed to download $WINTUN_URL" >&2
          exit 1
        fi
      fi
      echo "$WINTUN_SHA  $ZIP" | sha256sum -c -
      if command -v unzip >/dev/null; then
        unzip -o -j "$ZIP" 'wintun/bin/amd64/wintun.dll' -d "$OUT/windows"
      elif [ "$is_windows" = true ]; then
        # Git Bash ships GNU tar (no zip support) but Windows' bsdtar reads zip;
        # it needs a native path, not the MSYS one.
        WZIP="$(cygpath -m "$ZIP")"
        ( cd "$TMPD" && /c/Windows/System32/tar.exe -xf "$WZIP" wintun/bin/amd64/wintun.dll )
        cp "$TMPD/wintun/bin/amd64/wintun.dll" "$OUT/windows/"
      else
        echo "need unzip to extract $ZIP" >&2
        exit 1
      fi
      rm -rf "$TMPD"
      trap - EXIT
      [ -f "$OUT/windows/wintun.dll" ] || { echo "wintun.dll missing after extraction" >&2; exit 1; }
    fi
    ;;
  macos)
    for arch in arm64 amd64; do
      CGO_ENABLED=1 GOOS=darwin GOARCH=$arch MACOSX_DEPLOYMENT_TARGET=11.0 \
        go build -buildmode=c-shared -tags "$TAGS" -ldflags "$LDFLAGS" \
        -o "$OUT/macos/$arch/libkuputun.dylib" ./cmd/libkuputun
    done
    lipo -create -output "$OUT/macos/libkuputun.dylib" "$OUT/macos/arm64/libkuputun.dylib" "$OUT/macos/amd64/libkuputun.dylib"
    install_name_tool -id "@rpath/libkuputun.dylib" "$OUT/macos/libkuputun.dylib"
    ;;
  *)
    echo "usage: $0 android|ios|linux|windows|macos" >&2
    exit 2
    ;;
esac
echo "native build done: $1"
