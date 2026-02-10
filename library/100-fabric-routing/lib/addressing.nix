# lib/addressing.nix
{ lib }:

let
  #
  # Determine index of a node within a 2-member p2p link
  # IMPORTANT: member order is SEMANTIC.
  # DO NOT sort. Topology-gen defines who is index 0 vs 1.
  #
  nodeIndex =
    node: members:
    let
      go =
        i: xs:
        if xs == [ ] then
          -1
        else if lib.head xs == node then
          i
        else
          go (i + 1) (lib.tail xs);
    in
    go 0 members;

  #
  # Hex digit table
  #
  digits = [
    "0"
    "1"
    "2"
    "3"
    "4"
    "5"
    "6"
    "7"
    "8"
    "9"
    "a"
    "b"
    "c"
    "d"
    "e"
    "f"
  ];

  #
  # Convert integer → lowercase hex string
  #
  toHex =
    n:
    let
      go =
        x:
        if x < 16 then
          [ (lib.elemAt digits x) ]
        else
          (go (builtins.div x 16)) ++ [ (lib.elemAt digits (x - (builtins.div x 16) * 16)) ];
    in
    builtins.concatStringsSep "" (go n);

  #
  # Zero-pad string to width w
  #
  zpad =
    w: s:
    let
      len = builtins.stringLength s;
      zeros = builtins.concatStringsSep "" (builtins.genList (_: "0") (lib.max 0 (w - len)));
    in
    zeros + s;

  #
  # Encode transit VLAN ID into ffXX IPv6 hextet
  #
  transitHextet =
    tvid:
    if tvid < 0 || tvid > 255 then
      throw "addressing: transit vlanId ${toString tvid} out of range (0..255)"
    else
      "ff${zpad 2 (toHex tvid)}";

in
{
  #
  # EXPORTS
  #
  inherit transitHextet;

  #
  # Tenant LAN addressing
  #
  mkTenantV4 = { v4Base, vlanId }: "${v4Base}.${toString vlanId}.1/24";

  mkTenantV6 = { ulaPrefix, vlanId }: "${ulaPrefix}:${toString vlanId}::1/64";

  #
  # Point-to-point IPv4 (/31)
  # Index 0 → .2 (policy side)
  # Index 1 → .3 (peer side)
  #
  mkP2P4 =
    {
      v4Base,
      vlanId,
      node,
      members,
    }:
    let
      idx = nodeIndex node members;
    in
    if idx < 0 || idx > 1 then
      throw "p2p requires exactly 2 members and node must be a member"
    else
      "${v4Base}.${toString vlanId}.${toString (idx + 2)}/31";

  #
  # Point-to-point IPv6 (/127, ffXX encoding)
  # Index 0 → ::2 (policy side)
  # Index 1 → ::3 (peer side)
  #
  mkP2P6 =
    {
      ulaPrefix,
      vlanId,
      node,
      members,
    }:
    let
      idx = nodeIndex node members;
    in
    if idx < 0 || idx > 1 then
      throw "p2p requires exactly 2 members and node must be a member"
    else
      "${ulaPrefix}:${transitHextet vlanId}::${toString (idx + 2)}/127";
}
