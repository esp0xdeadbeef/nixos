{ config
, lib
, pkgs
, ...
}:
{
  boot.initrd.systemd.services.cryptswap-keyfile = {
    description = "Stage cryptswap keyfile from persisted root";
    requiredBy = [ "systemd-cryptsetup@cryptswap.service" ];
    after = [ "systemd-cryptsetup@root.service" ];
    before = [
      "systemd-cryptsetup@cryptswap.service"
    ];
    unitConfig.DefaultDependencies = false;
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /cryptswap-persist /run
      mount -o subvol=/persist,ro /dev/mapper/root /cryptswap-persist
      install -m 0400 /cryptswap-persist/etc/diskunlock/cryptswap.key /run/cryptswap.key
      umount /cryptswap-persist
    '';
  };

  boot.initrd.luks.devices = lib.mkForce {
    root = {
      device = "/dev/disk/by-partlabel/disk-nvme0n1-luks";
      allowDiscards = true;
    };
    cryptswap = {
      device = "/dev/disk/by-partlabel/disk-nvme0n1-swap";
      allowDiscards = true;
      keyFile = "/run/cryptswap.key";
      crypttabExtraOpts = [
        "nofail"
        "tries=1"
        "timeout=5s"
        "x-systemd.device-timeout=5s"
      ];
    };
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
