#!/usr/bin/env bash
set -euo pipefail

# Build + push using NDK toolchain from nix
NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE=1 \
nix shell --impure nixpkgs#androidsdk --command bash -lc '
  set -euo pipefail
  ANDROID_SDK_ROOT=$(nix eval --raw --impure nixpkgs#androidsdk.outPath)
  ANDROID_SDK_REAL=$ANDROID_SDK_ROOT/libexec/android-sdk
  NDK_BIN=$(echo "$ANDROID_SDK_REAL"/ndk/*/toolchains/llvm/prebuilt/linux-x86_64/bin)
  export PATH="$NDK_BIN:$PATH"

  x86_64-linux-android34-clang -shared -fPIC example-ld-preload.c -o example-ld-preload.so
'

adb push example-ld-preload.so /data/local/tmp/example-ld-preload.so

# If emulator supports it, become root
adb root >/dev/null 2>&1 || true
adb shell id

PKG=com.android.documentsui
adb shell "setprop wrap.$PKG 'logwrapper LD_PRELOAD=/data/local/tmp/example-ld-preload.so'"
adb shell "am force-stop $PKG"
adb shell "am start -n $PKG/.LauncherActivity"


# Install wrap + restart target
adb shell setprop wrap.com.android.documentsui "logwrapper LD_PRELOAD=/data/local/tmp/example-ld-preload.so"
adb shell am force-stop com.android.documentsui
adb shell rm -f /data/local/tmp/ld-prehook.txt
adb shell am start -n com.android.documentsui/.LauncherActivity

sleep 1
adb shell cat /data/local/tmp/ld-prehook.txt || true

