{ config, ... }:
let
  pickNetwork =
    name:
    let
      network = config.systemd.network.networks.${name};
    in
    {
      matchConfig = network.matchConfig or { };
      networkConfig = network.networkConfig or { };
      bridgeVLANs = network.bridgeVLANs or [ ];
    };

  pickNetdev =
    name:
    let
      netdev = config.systemd.network.netdevs.${name};
    in
    {
      netdevConfig = netdev.netdevConfig or { };
      bridgeConfig = netdev.bridgeConfig or { };
      vlanConfig = netdev.vlanConfig or { };
    };

  adapter = {
    netdevs = {
      eth02 = pickNetdev "10-eth0.2";
      vlan2 = pickNetdev "20-vlan2";
      clabTrunk = pickNetdev "10-clab-trunk";
    };
    networks = {
      eth0 = pickNetwork "10-eth0";
      eth02 = pickNetwork "20-eth0.2";
      vlan2 = pickNetwork "30-vlan2";
      clab0 = pickNetwork "21-clab0";
    };
    containerExtraVeths = config.containers."s-router-clab-container".extraVeths;
    nat = {
      enable = config.networking.nat.enable;
      externalInterface = config.networking.nat.externalInterface;
      internalInterfaces = config.networking.nat.internalInterfaces;
    };
  };

  expectedHash = "7bcb7933852106136a2d4c12129c7f28fcb7d741d6fbf3e9c3e68f33a4c3245b";
  actualHash = builtins.hashString "sha256" (builtins.toJSON adapter);
in
{
  assertions = [
    {
      assertion = actualHash == expectedHash;
      message = ''
        s-router-clab host adapter changed.
        Expected ${expectedHash}, got ${actualHash}.
        Host management must stay on vlan2, nested CLAB management may attach
        only through mgmt0 DHCP, and clab0 must stay on clab-trunk without VLAN2.
        Change container networking only with matching guard/test evidence.
      '';
    }
  ];
}
