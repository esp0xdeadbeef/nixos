{ lib }:

let
  splitCIDR =
    cidr:
    let
      parts = lib.splitString "/" cidr;
    in
    if builtins.length parts != 2 then
      abort "net/cidr: expected CIDR, got '${cidr}'"
    else
      {
        address = builtins.elemAt parts 0;
        prefixLength = builtins.elemAt parts 1;
      };

  firstIPv4InSubnet =
    cidr:
    let
      parsed = splitCIDR cidr;
      octets = lib.splitString "." parsed.address;
    in
    if builtins.length octets != 4 then
      abort "net/cidr: expected IPv4 CIDR, got '${cidr}'"
    else
      "${builtins.elemAt octets 0}.${builtins.elemAt octets 1}.${builtins.elemAt octets 2}.1/${parsed.prefixLength}";

  firstIPv6InSubnet =
    cidr:
    let
      parsed = splitCIDR cidr;
    in
    if lib.hasSuffix "::" parsed.address then
      "${parsed.address}1/${parsed.prefixLength}"
    else
      abort "net/cidr: firstIPv6InSubnet expects a subnet base ending in '::', got '${cidr}'";
in
{
  inherit
    splitCIDR
    firstIPv4InSubnet
    firstIPv6InSubnet
    ;
}
