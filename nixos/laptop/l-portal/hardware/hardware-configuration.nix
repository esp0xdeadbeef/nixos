{ config
, lib
, pkgs
, ...
}:
let
  cryptswapBackingDevice = "/dev/disk/by-partlabel/disk-nvme0n1-swap";
  cryptswapBackingUnit = "dev-disk-by\\x2dpartlabel-disk\\x2dnvme0n1\\x2dswap.device";
  cryptswapKeyFile = "/persist/etc/diskunlock/cryptswap.key";
  cryptswapMapper = "cryptswap";
  cryptswapSwapUnit = "dev-mapper-cryptswap.swap";
in
{

  boot.initrd.luks.devices = lib.mkForce {
    root = {
      device = "/dev/disk/by-partlabel/disk-nvme0n1-luks";
      allowDiscards = true;
    };
  };

  systemd.services.cryptswap-unlock = {
    description = "Unlock encrypted swap from persisted root keyfile";
    requiredBy = [ cryptswapSwapUnit ];
    requires = [ cryptswapBackingUnit ];
    after = [
      cryptswapBackingUnit
      "persist.mount"
    ];
    before = [ cryptswapSwapUnit ];
    unitConfig = {
      DefaultDependencies = false;
      RequiresMountsFor = [ cryptswapKeyFile ];
    };
    path = [
      pkgs.cryptsetup
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if cryptsetup status ${cryptswapMapper} >/dev/null 2>&1; then
        exit 0
      fi

      cryptsetup open --allow-discards \
        ${cryptswapBackingDevice} \
        ${cryptswapMapper} \
        --key-file ${cryptswapKeyFile}
    '';
  };

  networking.useDHCP = lib.mkDefault true;

  system.stateVersion = "24.11";
  services.openssh.enable = true;
  environment.systemPackages = with pkgs; [
    btrfs-progs
    dosfstools
    e2fsprogs
    exfatprogs
    parted
    util-linux
  ];
}
