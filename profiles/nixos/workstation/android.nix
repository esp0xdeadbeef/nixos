{ config
, lib
, pkgs
, ...
}:

let
  cfg = config.local.workstation.android;
in
{
  options.local.workstation.android = {
    enable = lib.mkEnableOption "lightweight Android workstation support";

    emulator.enable = lib.mkEnableOption "the composed Android SDK and emulator in the system profile";
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.config.android_sdk.accept_license = true;

    programs.kdeconnect.enable = true;

    environment.systemPackages =
      [ pkgs.android-tools ]
      ++ lib.optionals cfg.emulator.enable [
        pkgs.android-emulator-sdk
      ];
  };
}
