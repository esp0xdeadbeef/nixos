# lib/routing/tenant-lan.nix
{ lib, ulaPrefix }:

topo:

let
  links = topo.links or { };

  getTenantVid = ep: if ep ? tenant && ep.tenant ? vlanId then ep.tenant.vlanId else null;

  # Extract normalized delegated /48 base (same logic as wan-detection)
  delegatedV6 =
    let
      normalize48 =
        addr:
        let
          parts = lib.splitString "/" addr;
          ip = builtins.elemAt parts 0;
          plen = builtins.elemAt parts 1;
          hextets = lib.take 3 (lib.splitString ":" ip);
        in
        if plen != "48" then null else lib.concatStringsSep ":" hextets;

      candidates = lib.concatMap (
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
    if candidates == [ ] then null else lib.head candidates;

in
topo
// {
  links = lib.mapAttrs (
    _: l:
    if l.kind == "lan" && lib.length (l.members or [ ]) == 1 then
      let
        n = lib.head l.members;
        ep = l.endpoints.${n};
        vid = getTenantVid ep;

        ula64 = "${ulaPrefix}:${toString vid}::/64";

        gua64 = if delegatedV6 != null && vid != null then "${delegatedV6}:${toString vid}::/64" else null;

        guaAddr =
          if delegatedV6 != null && vid != null then "${delegatedV6}:${toString vid}::1/64" else null;
      in
      l
      // {
        endpoints = l.endpoints // {
          "${n}" =
            ep
            // {
              ra6Prefixes = lib.unique (
                (ep.ra6Prefixes or [ ]) ++ [ ula64 ] ++ lib.optional (gua64 != null) gua64
              );
            }
            // lib.optionalAttrs (guaAddr != null) {
              addr6Public = guaAddr;
            };
        };
      }
    else
      l
  ) links;
}
