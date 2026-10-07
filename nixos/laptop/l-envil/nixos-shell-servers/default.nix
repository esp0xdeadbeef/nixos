{
  imports = [
    ./servers.nix
  ];

  # Start the cobalt site router only while its WAN adapter has carrier, the
  # same shape as s-sigma's `eno1-router-vms` rule on s-router-prod.  The WAN
  # NIC is pinned to the role name cobalt-wan0 in
  # hardware/cobalt-bridges.nix and enslaved into br-cobalt-wan.
  services.nixosShellVmManager.carrierControls.cobalt-wan0-router-vms = {
    interface = "cobalt-wan0";
    requiredInterfaces = [
      "br-cobalt-lan"
      "br-cobalt-wan"
    ];
    instances = [ "s-router-cobalt" ];
    pollIntervalSeconds = 5;
    description = "Start or stop the cobalt router VMs from the WAN adapter carrier";
  };
}
