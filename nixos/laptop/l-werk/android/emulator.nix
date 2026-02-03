{
  config,
  pkgs,
  lib,
  ...
}:

let
  androidPkgs = pkgs.androidenv.composeAndroidPackages {
    includeEmulator = true;
    includeSystemImages = true;

    platformVersions = [ "34" ];
    systemImageTypes = [ "default" ];
    abiVersions = [ "x86_64" ];
  };

  sdkRoot = "${androidPkgs.androidsdk}/libexec/android-sdk";
in
{
  nixpkgs.config.android_sdk.accept_license = true;

  programs.adb.enable = true;
  environment.systemPackages = [
    androidPkgs.androidsdk
    pkgs.qemu

    # Force wrapper to override real emulator
    (lib.hiPrio (
      pkgs.writeShellScriptBin "emulator" ''
        export ANDROID_HOME=${sdkRoot}
        export ANDROID_SDK_ROOT=${sdkRoot}
        exec ${sdkRoot}/emulator/emulator \
          -gpu swiftshader_indirect "$@"
      ''
    ))

    (lib.hiPrio (
      pkgs.writeShellScriptBin "emulator-headless" ''
        export ANDROID_HOME=${sdkRoot}
        export ANDROID_SDK_ROOT=${sdkRoot}
        exec ${sdkRoot}/emulator/emulator \
          -gpu swiftshader_indirect \
          -no-window \
          -no-audio \
          -writable-system \
          "$@"
      ''
    ))
    (lib.hiPrio (
      pkgs.writeShellScriptBin "emulator-start" ''
        export ANDROID_HOME=${sdkRoot}
        export ANDROID_SDK_ROOT=${sdkRoot}
        exec ${sdkRoot}/emulator/emulator -gpu swiftshader_indirect -avd $(avdmanager list avd | grep -i name | rev | awk '{print $1}' | rev)
      ''
    ))
  ];

  environment.sessionVariables = {
    ANDROID_HOME = sdkRoot;
    ANDROID_SDK_ROOT = sdkRoot;
  };
}
