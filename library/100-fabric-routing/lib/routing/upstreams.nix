# lib/routing/upstreams.nix
{ lib }:

topo:

let
  links = topo.links or { };

  isUpstream = l: (l.kind or null) == "upstream";

  getEp = l: n: (l.endpoints or { }).${n} or { };
  setEp =
    l: n: ep:
    l
    // {
      endpoints = (l.endpoints or { }) // {
        "${n}" = ep;
      };
    };

in
topo
// {
  links = lib.mapAttrs (
    _: l:
    if !isUpstream l then
      l
    else
      let
        node = lib.head (l.members or [ ]);
        ep = getEp l node;
        up = ep.upstream or null;
      in
      if up == null then
        l
      else
        setEp l node (
          ep
          // {
            routes4 = [
              {
                dst = "0.0.0.0/0";
                viaUpstream = up;
              }
            ];
            routes6 = [
              {
                dst = "::/0";
                viaUpstream = up;
              }
            ];
          }
        )
  ) links;
}
