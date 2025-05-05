{ config, pkgs, ... }:

{
  # 1) Load FUSE and allow non-root mounts
  boot.kernelModules = [ "fuse" ];
  programs.fuse = {
    enable = true;
    userAllowOther = true;  # permits --allow-other in bindfs
  }; # see: `https://nixos.org/manual/nixos/stable/#sec-system-fuse`

  # 2) Ensure bindfs itself is available
  environment.systemPackages = with pkgs; [
    bindfs
  ];

  # 3) Declarative bindfs mount
  fileSystems."/home/deadbeef/.local/share/lxc/osep-lxc/rootfs/mnt" = {
    device  = "/home/deadbeef/github/osep/shared";
    fsType  = "fuse.bindfs";
    options = [
      "uid_offset=100000"
      "gid_offset=100900"
      "allow_other"
      "nonempty"
    ];
    # ensure the mountpoint directory exists first
    depends = [ "/home/deadbeef/.local/share/lxc/osep-lxc/rootfs" ];
  }; # see: `https://nixos.org/manual/nixos/stable/#sec-declarative-file-systems`
}
