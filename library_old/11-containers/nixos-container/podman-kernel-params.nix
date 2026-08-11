# ./host/impermanence.nix
{ config, lib, ... }:

{
  boot.kernelParams = [
    "systemd.unified_cgroup_hierarchy=1"
    "cgroup_no_v1=all"
  ];
}
