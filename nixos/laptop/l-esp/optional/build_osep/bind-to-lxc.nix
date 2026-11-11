{
  # The OSEP bindfs share, declared as data so that the sudoers NOPASSWD rule
  # and the shutdown teardown are generated from it (see
  # library/01-general/virtualization-as-host/lxc.nix).
  #
  # home-manager/l-esp/configs/build_osep/start-lxc.nix consumes this and
  # refuses to build if the values disagree, so the argv sudo authorises and
  # the argv the unit runs stay identical.
  local.containerNetwork.bindMounts = [
    {
      source = "/home/deadbeef/github/osep/shared";
      target = "/home/deadbeef/.local/share/lxc/osep-lxc/rootfs/mnt";
      user = "deadbeef";
      container = "osep-lxc";
    }
  ];
}
