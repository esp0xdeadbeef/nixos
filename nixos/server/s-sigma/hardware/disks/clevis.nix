{ profiles, ... }:

{
  imports = [ profiles.nixos.boot.clevis-tang-unlock ];

  local.boot.clevisTangUnlock = {
    enable = true;
    deviceName = "crypted";
    secretFile = ./nvme0n1p1.jwe;
    tang = {
      host = "192.168.1.75";
      port = 7500;
    };
    network = {
      interface = "eno4";
      address = "192.168.1.98/24";
    };
    kernelModules = [
      "bnx2"
      "bnx2x"
      "ixgbe"
    ];
  };
}
