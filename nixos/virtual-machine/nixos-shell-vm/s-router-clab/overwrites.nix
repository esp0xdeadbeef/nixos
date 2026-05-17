{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  labInventory = import "${inputs.network-labs}/labs/lab-s-sigma/s-router-test-three-site/getResolvedInventory.nix" {
    renderer = "nixos";
  };

  clabHostBridgeNetworks = labInventory.deployment.hosts.s-router-clab.bridgeNetworks or { };

  clabTenantVlanIds = lib.unique (
    lib.mapAttrsToList (_: bridge: toString bridge.vlan) (
      lib.filterAttrs (
        _: bridge:
        (bridge.mode or null) == "vlan" && (bridge.parent or null) == "eth0" && bridge ? vlan
      ) clabHostBridgeNetworks
    )
  );

  clabExternalVlanIds = [
    "2"
    "4"
    "5"
  ];

  clabContainerExternalVlanIds = [
    "4"
    "5"
  ];

  clabTrunkVlanIds = lib.unique (clabExternalVlanIds ++ clabTenantVlanIds);
  clabContainerTrunkVlanIds = lib.unique (clabContainerExternalVlanIds ++ clabTenantVlanIds);

  mkBridgeVlan = vlanId: { VLAN = vlanId; };

  disabledHostVlanIds = [
    3
    4
    5
    6
    7
    8
    9
    1010
  ];

  disableHostVlan = vlanId:
    let
      id = toString vlanId;
    in
    {
      netdevs = {
        "10-eth0.${id}".enable = lib.mkForce false;
        "10-eth0-vlan${id}".enable = lib.mkForce false;
      };
      networks."20-eth0.${id}".enable = lib.mkForce false;
    };

  disabledHostVlans = lib.foldl' lib.recursiveUpdate { } (map disableHostVlan disabledHostVlanIds);
in
{
  systemd.network = {
    netdevs = disabledHostVlans.netdevs // {
      "10-clab-eth0".enable = lib.mkForce false;

      "10-clab-trunk" = {
        netdevConfig = {
          Name = "clab-trunk";
          Kind = "bridge";
        };
        bridgeConfig = {
          DefaultPVID = "none";
          VLANFiltering = true;
        };
      };

    };

    networks = disabledHostVlans.networks // {
      "10-eth0" = {
        matchConfig.Name = "eth0";
        networkConfig = {
          Bridge = "clab-trunk";
          DHCP = "no";
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
        };
        bridgeVLANs = map mkBridgeVlan clabTrunkVlanIds;
      };

      "20-clab-eth0".enable = lib.mkForce false;

      "20-clab-trunk" = {
        matchConfig.Name = "clab-trunk";
        networkConfig = {
          ConfigureWithoutCarrier = true;
          DHCP = "no";
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
        };
      };

      "30-vlan2" = {
        matchConfig.Name = "vlan2";
        networkConfig.DHCP = lib.mkForce "ipv4";
      };

      "21-clab0" = {
        matchConfig.Name = "clab0";
        bridgeVLANs = map mkBridgeVlan clabContainerTrunkVlanIds;
      };

    };
  };

  containers."${config.networking.hostName}-container".extraVeths = lib.mkForce {
    mgmt0.hostBridge = "vlan2";
    clab0.hostBridge = "clab-trunk";
  };

  networking.nat = {
    enable = true;
    externalInterface = "vlan2";
    internalInterfaces = [ "mgmt0" ];
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    gron
    jq
    ripgrep
  ];
}
