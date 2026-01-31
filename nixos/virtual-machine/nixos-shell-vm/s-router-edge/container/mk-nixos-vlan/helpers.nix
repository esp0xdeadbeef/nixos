{ lib }:
{
  stripCidr = s: lib.head (lib.splitString "/" s);

  ipv4Base3 =
    ip4:
    let
      oct = lib.splitString "." (lib.head (lib.splitString "/" ip4));
    in
    lib.concatStringsSep "." (lib.take 3 oct);

  defaultPool4 =
    ip4:
    let
      b = (lib.take 3 (lib.splitString "." (lib.head (lib.splitString "/" ip4))));
    in
    "${lib.concatStringsSep "." b}.100 - ${lib.concatStringsSep "." b}.200";

  isIPv4 = s: lib.hasInfix "." s;
  onlyIPv4 = xs: lib.filter (x: (builtins.isString x) && (lib.hasInfix "." x)) xs;

  # For /24 only (your current design). Example:
  # 192.168.1.1/24 -> 1.168.192.in-addr.arpa.
  reverseZoneV4_24 =
    ip4:
    let
      base = lib.head (lib.splitString "/" ip4);
      plen = lib.last (lib.splitString "/" ip4);
      oct = lib.splitString "." base;
      a = lib.elemAt oct 0;
      b = lib.elemAt oct 1;
      c = lib.elemAt oct 2;
    in
    if plen != "24" then
      abort "reverseZoneV4_24 only supports /24, got /${plen} for ${ip4}"
    else
      "${c}.${b}.${a}.in-addr.arpa.";
}

