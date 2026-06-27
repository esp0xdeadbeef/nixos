{ lib, profiles, ... }:

let
  jweFile = ./root-raid0.jwe;
  jweExists = builtins.pathExists jweFile;
in
{
  imports = [ profiles.nixos.boot.clevis-tang-unlock ];

  local.boot.clevisTangUnlock = {
    # The final install enables this after clevis-init-jwe.sh writes
    # root-raid0.jwe. Until then tau can still evaluate during bootstrap.
    enable = jweExists;
    deviceName = "crypted";
    secretFile = lib.mkIf jweExists jweFile;
    tang = {
      host = "192.168.1.75";
      port = 7500;
    };
    network = {
      interface = "eno4";
      # This is tau's initrd client address. The Tang server remains .75.
      address = "192.168.1.70/24";
    };
    kernelModules = [
      "bnx2"
      "bnx2x"
      "ixgbe"
    ];
  };
}
