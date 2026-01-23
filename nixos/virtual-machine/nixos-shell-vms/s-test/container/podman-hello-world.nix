{ config, pkgs, ... }:

{
  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    dockerCompat = false;
  };

boot.kernelParams = [
  "systemd.unified_cgroup_hierarchy=1"
  "cgroup_no_v1=all"
];



  virtualisation.oci-containers.backend = "podman";

  virtualisation.oci-containers.containers.hello-world = {
    image = "quay.io/podman/hello";
    autoStart = true;
  };

}
