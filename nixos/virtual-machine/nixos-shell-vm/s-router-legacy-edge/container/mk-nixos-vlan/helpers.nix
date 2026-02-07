{ lib }:
{
  # Strip CIDR suffix
  stripCidr = s: lib.head (lib.splitString "/" s);

  # Take first 3 octets of an IPv4 address
  ipv4Base3 =
    ip4:
    let
      oct = lib.splitString "." (lib.head (lib.splitString "/" ip4));
    in
    lib.concatStringsSep "." (lib.take 3 oct);

  # Default DHCP pool (.100–.200)
  defaultPool4 =
    ip4:
    let
      b = lib.take 3 (lib.splitString "." (lib.head (lib.splitString "/" ip4)));
    in
    "${lib.concatStringsSep "." b}.100 - ${lib.concatStringsSep "." b}.200";

  # IPv4 helpers
  isIPv4 = s: lib.hasInfix "." s;
  onlyIPv4 = xs: lib.filter (x: builtins.isString x && lib.hasInfix "." x) xs;

  /*
    Reverse DNS zone generator (INTENT-BASED)

    - Does NOT care about prefix length
    - Generates a /24-style reverse zone based on the network octet
    - Caller decides WHETHER to generate a reverse zone
      (e.g. no PTRs for transit / WAN / p2p)
  */
  reverseZoneV4 =
    ip4:
    let
      base = lib.head (lib.splitString "/" ip4);
      oct = lib.splitString "." base;
    in
    "${lib.elemAt oct 2}.${lib.elemAt oct 1}.${lib.elemAt oct 0}.in-addr.arpa.";
}

