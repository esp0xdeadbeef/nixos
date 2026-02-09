# lib/routing/p2p.nix
{ lib }:

{
  peerEp =
    l: me:
    let
      ms = l.members or [ ];
    in
    if lib.length ms != 2 then
      throw "p2p link '${l.name or "?"}' must have 2 members"
    else if lib.head ms == me then
      builtins.elemAt ms 1
    else if builtins.elemAt ms 1 == me then
      lib.head ms
    else
      throw "node '${me}' not in p2p link '${l.name or "?"}'";
}
