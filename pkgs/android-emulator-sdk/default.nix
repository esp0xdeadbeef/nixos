{ androidenv
, android-tools
, bashInteractive
, lib
, qemu
, symlinkJoin
, writeShellApplication
}:

let
  androidPkgs = androidenv.composeAndroidPackages {
    includeEmulator = true;
    includeSystemImages = true;

    platformVersions = [ "34" ];
    systemImageTypes = [ "default" ];
    abiVersions = [ "x86_64" ];
  };

  sdkRoot = "${androidPkgs.androidsdk}/libexec/android-sdk";

  androidShell = writeShellApplication {
    name = "android-shell";
    runtimeInputs = [
      androidPkgs.androidsdk
      android-tools
      qemu
    ];
    text = ''
      export ANDROID_HOME=${sdkRoot}
      export ANDROID_SDK_ROOT=${sdkRoot}
      export PATH=${sdkRoot}/cmdline-tools/latest/bin:${sdkRoot}/platform-tools:${sdkRoot}/emulator:$PATH
      exec "''${SHELL:-${lib.getExe' bashInteractive "bash"}}" "$@"
    '';
  };

  emulator = writeShellApplication {
    name = "emulator";
    text = ''
      export ANDROID_HOME=${sdkRoot}
      export ANDROID_SDK_ROOT=${sdkRoot}
      exec ${sdkRoot}/emulator/emulator -gpu swiftshader_indirect "$@"
    '';
  };

  emulatorHeadless = writeShellApplication {
    name = "emulator-headless";
    text = ''
      export ANDROID_HOME=${sdkRoot}
      export ANDROID_SDK_ROOT=${sdkRoot}
      exec ${sdkRoot}/emulator/emulator \
        -gpu swiftshader_indirect \
        -no-window \
        -no-audio \
        -writable-system \
        "$@"
    '';
  };

  emulatorStart = writeShellApplication {
    name = "emulator-start";
    runtimeInputs = [ androidPkgs.androidsdk ];
    text = ''
      export ANDROID_HOME=${sdkRoot}
      export ANDROID_SDK_ROOT=${sdkRoot}
      avd="$(avdmanager list avd | awk -F': ' 'tolower($1) ~ /name/ { name=$2 } END { print name }')"
      if [ -z "$avd" ]; then
        echo "No Android virtual device found." >&2
        exit 1
      fi
      exec ${sdkRoot}/emulator/emulator -gpu swiftshader_indirect -avd "$avd"
    '';
  };
in
symlinkJoin {
  name = "android-emulator-sdk";
  paths = [
    androidPkgs.androidsdk
    android-tools
    qemu
    androidShell
    emulator
    emulatorHeadless
    emulatorStart
  ];

  passthru = {
    inherit sdkRoot;
  };

  meta = {
    description = "Android SDK and emulator composition for ad-hoc workstation use";
    mainProgram = "android-shell";
  };
}
