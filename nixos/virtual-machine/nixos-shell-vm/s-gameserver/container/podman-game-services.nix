{ config, pkgs, ... }:

{
  virtualisation.oci-containers.backend = "podman";
  virtualisation.podman = {
    enable = true;

    # HARD ISOLATION
    defaultNetwork.settings = {
      network_backend = "slirp4netns";
    };

    extraPackages = [
      pkgs.slirp4netns
      pkgs.fuse-overlayfs
    ];
  };
}
