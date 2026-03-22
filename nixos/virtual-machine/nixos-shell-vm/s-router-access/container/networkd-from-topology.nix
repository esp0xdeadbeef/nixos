{
  config,
  lib,
  vlanId,
  policyAccessTransitBase,
  outPath,
  ...
}:

let
  addrImported = import "${outPath}/library/100-fabric-routing/lib/addressing.nix";
  addr =
    if builtins.isFunction addrImported then
      addrImported { inherit lib; }
    else
      addrImported;

  v4Base = "10.10";
  ulaPrefix = "fd42:dead:beef";

  tenantVlan = vlanId;
  transitVlan = policyAccessTransitBase + vlanId;

  lanAddr4 = "${v4Base}.${toString tenantVlan}.1/24";
  lanAddr6 = "${ulaPrefix}:${toString tenantVlan}::1/64";

  trAddr4 = "${v4Base}.${toString transitVlan}.3/31";
  trAddr6 = "${ulaPrefix}:${addr.transitHextet transitVlan}::3/127";

  trGw4 = "${v4Base}.${toString transitVlan}.2";
  trGw6 = "${ulaPrefix}:${addr.transitHextet transitVlan}::2";
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;

  systemd.network.networks = {

    "10-lan" = {
      matchConfig.Name = "lan-*";

      networkConfig = {
        DHCP = "no";
        IPv4Forwarding = true;
        IPv6Forwarding = true;
        IPv6AcceptRA = true;
        ConfigureWithoutCarrier = true;
      };

      linkConfig.RequiredForOnline = false;

      addresses = [
        { Address = lanAddr4; }
        { Address = lanAddr6; }
      ];
    };

    "20-transit" = {
      matchConfig.Name = "tr-*";

      networkConfig = {
        DHCP = "no";
        IPv4Forwarding = true;
        IPv6Forwarding = true;
        IPv6AcceptRA = false;
        ConfigureWithoutCarrier = true;
      };

      linkConfig.RequiredForOnline = false;

      addresses = [
        { Address = trAddr4; }
        { Address = trAddr6; }
      ];

      routes = [
        {
          Destination = "0.0.0.0/0";
          Gateway = trGw4;
        }
        {
          Destination = "::/0";
          Gateway = trGw6;
        }
      ];
    };
  };
}
