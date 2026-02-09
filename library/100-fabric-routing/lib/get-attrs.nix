# lib/get-attrs.nix
{ lib }:

let
  fabricsLib = import ./fabrics.nix { inherit lib; };
  site = import ./site-defaults.nix;

in
{
  # addressing inputs (required, no more hidden globals)
  ulaPrefix,
  tenantV4Base,

  # optional WAN defaults (can be overridden per WAN)
  defaultWan ? {
    ip4 = "10.255.255.2/29";
    gw4 = "10.255.255.1";
    ip6 = "${ulaPrefix}:1000::2/64";
    gw6 = "${ulaPrefix}:1000::1";
    acceptRA = true;
    publicPrefixFile = "/run/secrets/subnet-ipv6";
    dns = site.defaultWanDns;
  },

  # selection
  lans ? [ ],
  wans ? [ ],
  transits ? [ ],
}:

let
  mkLanAddrs = vlanId: {
    ip4 = "${tenantV4Base}.${toString vlanId}.1/24";
    ip6 = "${ulaPrefix}:${toString vlanId}::1/64";
  };

  mkTransit =
    { vlanId, node }:
    let
      # keep your old "edge vs other side" behavior, but remove hardcoded prefixes
      v4 =
        if node == "edge" then
          "${tenantV4Base}.${toString vlanId}.1/31"
        else
          "${tenantV4Base}.${toString vlanId}.2/31";

      v6 =
        if node == "edge" then
          "${ulaPrefix}:${toString vlanId}::1/127"
        else
          "${ulaPrefix}:${toString vlanId}::2/127";
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

  mkLan =
    vlanId:
    fabricsLib.applyDefaults vlanId (
      {
        id = vlanId;
        name = "lan${toString vlanId}";
        iface = "lan${toString vlanId}";
      }
      // mkLanAddrs vlanId
    );

  mkWan =
    vlanId:
    fabricsLib.applyDefaults vlanId (
      {
        name = "wanA";
        mark = toString vlanId;
        iface = "lan${toString vlanId}";
      }
      // defaultWan
    );

in
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
