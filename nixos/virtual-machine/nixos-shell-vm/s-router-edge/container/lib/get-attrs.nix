# lib/get-attrs.nix
{ lib }:

let
  fabricsLib = import ./fabrics.nix { inherit lib; };
  site = import ./site-defaults.nix;

  #
  # Addressing schemes
  #
  mkLanAddrs = vlanId: {
    ip4 = "10.10.${toString vlanId}.1/24";
    ip6 = "fd42:dead:beef:${toString vlanId}::1/64";
  };

  #
  # Transit generator (EXPLICIT SIDE)
  #
  mkTransit =
    { vlanId, node }:
    let
      v4 = if node == "edge" then "10.10.${toString vlanId}.1/30" else "10.10.${toString vlanId}.2/30";

      v6 =
        if node == "edge" then
          "fd42:dead:beef:${toString vlanId}::1/64"
        else
          "fd42:dead:beef:${toString vlanId}::2/64";
    in
    fabricsLib.applyDefaults vlanId {
      id = vlanId;
      name = "lan${toString vlanId}";
      iface = "lan${toString vlanId}";
      ip4 = v4;
      ip6 = v6;

      dhcp4 = false;
      ra6 = false;
      transit = true;
    };

  #
  # LAN generator
  #
  mkLan =
    vlanId:
    let
      base = {
        id = vlanId;
        name = "lan${toString vlanId}";
        iface = "lan${toString vlanId}";
      };
    in
    fabricsLib.applyDefaults vlanId (base // mkLanAddrs vlanId);

  #
  # WAN generator
  #
  mkWan =
    vlanId:
    fabricsLib.applyDefaults vlanId {
      name = "wanA";
      mark = toString vlanId;
      iface = "lan${toString vlanId}";

      ip4 = "10.255.255.2/29";
      gw4 = "10.255.255.1";

      ip6 = "fd42:dead:beef:1000::2/64";
      gw6 = "fd42:dead:beef:1000::1";

      acceptRA = true;
      publicPrefixFile = "/run/secrets/subnet-ipv6";
      dns = site.defaultWanDns;
    };

in
#
# Public API
#
# getAttrs {
#   lans     = [ 10 20 ];
#   wans     = [ 1010 ];
#   transits = [ { vlanId = 100; node = "edge"; } ];
# }
#
{
  lans ? [ ],
  wans ? [ ],
  transits ? [ ],
}:

{
  domain = site.domain;

  lans = map mkLan lans;
  wans = map mkWan wans;
  transits = map mkTransit transits;

  _meta = {
    lanFabrics = map fabricsLib.fabricKeyForVlan lans;
    wanFabrics = map fabricsLib.fabricKeyForVlan wans;
    transitFabrics = map (t: fabricsLib.fabricKeyForVlan t.vlanId) transits;
  };
}
