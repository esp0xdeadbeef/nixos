{
  config,
  lib,
  username,
  ...
}:

let
  homeDir = "/home/${username}";
in
{
  # boot.initrd.persistentStorage.enable = true;

  # fileSystems."/" = lib.mkForce {
  #   device = "none";
  #   fsType = "tmpfs";
  #   options = [
  #     "defaults"
  #     "mode=755"
  #     "size=4G"
  #   ];
  # };


  # fileSystems."/persist" = {
  #   # select your root partition and add a label with:
  #   # e2label /dev/mapper/luks-b5d59382-e651-4a67-b490-730f085e9706
  #   # PERSIST
  #   device = "/dev/disk/by-label/PERSIST";
  #   fsType = "ext4";
  #   neededForBoot = true;
  # };


  # environment.persistence."/persist".directories = [
  #   homeDir
  #   "/root"
  #   "/etc/ssh"
  #   "/var/lib/nixos"
  # ];

  # environment.persistence."/persist".files = [
  #   "/etc/machine-id"
  # ];
}
