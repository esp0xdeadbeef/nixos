{ lib
, pkgs
, profiles
, ...
}:
{
  imports = [
    profiles.nixos.server.dell-vm-host
    profiles.nixos.server.no-sleep
    profiles.nixos.llm-clients.agents
    profiles.nixos.network.nebula-mesh
    profiles.nixos.virtualization.pci-passthrough

    ./libvirt.nix
    ./nixos-shell-servers
    ./hardware
    ./connect-nas
  ];

  boot.swraid = {
    # Disko creates the LUKS container on this mdraid array; the initrd must
    # assemble it before cryptsetup can find the root device UUID.
    enable = true;
    mdadmConf = ''
      ARRAY /dev/md/root metadata=1.2 UUID=82520a72:9a366735:99afae75:870b517f
      PROGRAM ${pkgs.coreutils}/bin/true
    '';
  };

  # Keep large, long-running Android source and build closures available
  # between sessions. Keep failed sandboxes for late-stage Android build
  # diagnosis; unlike store paths, these require explicit manual cleanup.
  # Re-enable automatic GC and disable failed-build retention after the Karen
  # port stabilizes.
  nix.gc.automatic = lib.mkForce false;
  nix.settings = {
    extra-sandbox-paths = [ "/var/cache/ccache" ];
    keep-failed = true;
  };
  systemd.tmpfiles.rules = [
    "d /var/cache/ccache 2770 root nixbld -"
    "f+ /var/cache/ccache/ccache.conf 0660 root nixbld - max_size = 400G"
  ];
  warnings = lib.mkAfter [
    "s-tau: automatic Nix GC is disabled for the Karen LineageOS port. Review and re-enable it no later than 2027-07-25 to prevent unbounded Nix store growth."
    "s-tau: failed Nix sandboxes are retained for the Karen LineageOS port. Review /nix/var/nix/builds and disable keep-failed no later than 2027-07-25 to prevent unbounded scratch-space growth."
    "s-tau: the persistent Robotnix compiler cache may grow to 400 GB. Review /persist/var/cache/ccache and remove its persistence and sandbox exception no later than 2027-07-25 when the Karen port stabilizes."
  ];

  local.virtualization.pciPassthrough = {
    enable = true;
    dmaEntryLimit = 1048576;
    devices.tesla-p100 = {
      pciAddress = "0000:03:00.0";
      vmName = "s-llm-inference";
      lateHotplug = {
        enable = true;
        memoryReserve = "32M";
        prefetchableMemoryReserve = "32G";
      };
    };
  };

  system.stateVersion = "25.11";
}
