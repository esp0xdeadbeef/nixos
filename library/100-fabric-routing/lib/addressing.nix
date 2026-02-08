# lib/addressing.nix
{ lib, site }:

let
  nodeIndex =
    node: members:
      let
        sorted = lib.sort lib.lessThan members;
        go = i: xs:
          if xs == [] then -1
          else if lib.head xs == node then i
          else go (i + 1) (lib.tail xs);
      in
      go 0 sorted;

  digits = [ "0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "a" "b" "c" "d" "e" "f" ];

  toHex =
    n:
      let
        go = x:
          if x < 16 then lib.elemAt digits x
          else
            (go (builtins.div x 16))
            + (lib.elemAt digits (x - (builtins.div x 16) * 16));
      in
      if n == 0 then "0" else go n;

  zpad =
    w: s:
      let
        len = builtins.stringLength s;
        zeros = builtins.concatStringsSep "" (builtins.genList (_: "0") (lib.max 0 (w - len)));
      in
      zeros + s;

  # NEW RULE: transit IPv6 hextet = "ff" + hex2(vlanId)
  # Requires vlanId 0..255 so we stay inside a single 16-bit hextet cleanly.
  transitHextet =
    tvid:
      if tvid < 0 || tvid > 255 then
        throw "addressing: transit vlanId ${toString tvid} out of range (0..255) for ffXX encoding"
      else
        "ff${zpad 2 (toHex tvid)}";

in
{
  tenantV4 = vid:
    "${site.tenant.v4Base}.${toString vid}.1/${toString site.tenant.v4PrefixLen}";

  tenantV6 = vid:
    "${site.ula.prefix}:${toString vid}::1/${toString site.tenant.v6PrefixLen}";

  mkP2P4 =
    { vlanId, node, members }:
      let idx = nodeIndex node members;
      in
      if idx < 0 || idx > 1 then throw "p2p requires exactly 2 members"
      else
        "${site.transit.v4Base}.${toString vlanId}.${toString idx}/${toString site.transit.v4PrefixLen}";

  mkP2P6 =
    { vlanId, node, members }:
      let idx = nodeIndex node members;
      in
      if idx < 0 || idx > 1 then throw "p2p requires exactly 2 members"
      else
        "${site.ula.prefix}:${transitHextet vlanId}::${toString idx}/${toString site.transit.v6PrefixLen}";
}

