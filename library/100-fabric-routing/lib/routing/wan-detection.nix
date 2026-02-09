# lib/routing/wan-detection.nix
{ lib }:

links:

let
  # Normalize an addr6 like "2001:db8:1234::2/48"
  # into a pure /48 base: "2001:db8:1234"
  normalize48 =
    addr:
    let
      parts = lib.splitString "/" addr;
      ip = builtins.elemAt parts 0;
      plen = builtins.elemAt parts 1;

      hextets = lib.take 3 (lib.splitString ":" ip);
    in
    if plen != "48" then null else lib.concatStringsSep ":" hextets;

  delegatedPrefixes = lib.concatMap (
    l:
    lib.concatMap (
      ep:
      if ep ? addr6 && builtins.isString ep.addr6 then
        let
          base = normalize48 ep.addr6;
        in
        if base != null then [ base ] else [ ]
      else
        [ ]
    ) (lib.attrValues (l.endpoints or { }))
  ) (lib.attrValues links);

in
{
  delegatedV6 = if delegatedPrefixes == [ ] then null else lib.head delegatedPrefixes;
}
