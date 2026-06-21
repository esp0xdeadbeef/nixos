{ profiles, ... }:

{
  imports = [
    profiles.nixos.workstation.android
  ];

  local.workstation.android = {
    enable = true;
    emulator.enable = true;
  };
}
