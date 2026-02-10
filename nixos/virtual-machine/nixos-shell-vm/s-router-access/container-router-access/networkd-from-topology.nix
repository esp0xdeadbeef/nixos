# ./networkd-from-topology.nix
# FILE: container-router-access/networkd-from-topology.nix
{ config, lib, vlanId, policyAccessTransitBase, outPath, ... }:

let
  addr =
    import "${outPath}/library/100-fabric-routing/lib/addressing.nix" {
      inherit lib;
    };

  v4Base    = "10.10";
  ulaPrefix = "fd42:dead:beef";

  tenantVlan  = vlanId;
  transitVlan = policyAccessTransitBase + vlanId;

  # Access side addresses
  lanAddr4 = "${v4Base}.${toString tenantVlan}.1/24";
  lanAddr6 = "${ulaPrefix}:${toString tenantVlan}::1/64";

  # Transit side addresses (access = .3 / ::3)
  trAddr4 = "${v4Base}.${toString transitVlan}.3/31";
  trAddr6 = "${ulaPrefix}:${addr.transitHextet transitVlan}::3/127";

  # Policy side gateway (always .2 / ::2)
  trGw4 = "${v4Base}.${toString transitVlan}.2";
  trGw6 = "${ulaPrefix}:${addr.transitHextet transitVlan}::2";
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;

  systemd.network.networks = {

    #
    # Tenant LAN
    #
    "10-lan" = {
      matchConfig.Name = "lan-*";
      networkConfig = {
        DHCP = "no";
        IPv4Forwarding = true;
        IPv6Forwarding = true;
        IPv6AcceptRA = true;
        ConfigureWithoutCarrier = true;
      };
      addresses = [
        { Address = lanAddr4; }
        { Address = lanAddr6; }
      ];
    };

    #
    # Policy ↔ Access transit
    #
    "20-transit" = {
      matchConfig.Name = "tr-*";
      networkConfig = {
        DHCP = "no";
        IPv4Forwarding = true;
        IPv6Forwarding = true;
        IPv6AcceptRA = false;
        ConfigureWithoutCarrier = true;
      };
      addresses = [
        { Address = trAddr4; }
        { Address = trAddr6; }
      ];
      routes = [
        { Destination = "0.0.0.0/0"; Gateway = trGw4; }
        { Destination = "::/0";      Gateway = trGw6; }
      ];
    };
  };
}

