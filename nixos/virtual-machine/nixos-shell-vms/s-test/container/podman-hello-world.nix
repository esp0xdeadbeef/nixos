{ config, pkgs, ... }:

{
  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    dockerCompat = false;
    extraPackages = with pkgs; [ fuse-overlayfs ];
  };

  boot.kernelModules = [ "overlay" ];
  security.unprivilegedUsernsClone = true;

  boot.kernelParams = [
    "systemd.unified_cgroup_hierarchy=1"
    "cgroup_no_v1=all"
  ];

  systemd.services.podman-hello-world = {

    serviceConfig = {
      ExecStartPre = [
        "${pkgs.coreutils}/bin/sleep 5"
      ];
    };
  };
  virtualisation.oci-containers.backend = "podman";

  virtualisation.oci-containers.containers.hello-world = {
    image = "quay.io/podman/hello";
    autoStart = true;
  };

}
