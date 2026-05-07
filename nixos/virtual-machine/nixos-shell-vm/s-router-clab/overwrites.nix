{ pkgs, config, lib, ... }:
let
  disabledHostVlanIds = [
    2
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
      };

      "10-clab-trunk.2" = {
        netdevConfig = {
          Name = "clab-trunk.2";
          Kind = "vlan";
        };
        vlanConfig.Id = 2;
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
      };

      "20-clab-eth0".enable = lib.mkForce false;

      "20-clab-trunk" = {
        matchConfig.Name = "clab-trunk";
        networkConfig = {
          ConfigureWithoutCarrier = true;
          DHCP = "no";
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
          VLAN = [ "clab-trunk.2" ];
        };
      };

      "20-clab-trunk.2" = {
        matchConfig.Name = "clab-trunk.2";
        networkConfig = {
          Bridge = "vlan2";
          DHCP = "no";
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
        };
      };
    };
  };

  containers."${config.networking.hostName}-container".extraVeths = lib.mkForce {
    mgmt0 = {
      hostAddress = "10.233.222.1";
      localAddress = "10.233.222.2";
    };
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
