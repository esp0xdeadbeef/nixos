# lib/mk-l3-from-topo.nix
{
  lib,
  pkgs,
  ulaPrefix,
  tenantV4Base,
}:

nodeName: topo:

let
  links = topo.links or { };
  addr = import ./addressing.nix { inherit lib; };

  # MUST match mk-links-from-topo.nix exactly
  shortHash = s: builtins.substring 0 4 (builtins.hashString "sha256" s);

  kernelBridgeName =
    l:
    let
      base =
        if (l.kind or "") == "p2p" then
          "br-ce"
        else if (l.kind or "") == "l2" then
          "br-lg"
        else
          "br-x";

      ident = if l ? name then l.name else throw "link missing semantic name";
    in
    "${base}-${shortHash ident}";

  stripCidr = s: if s == null then null else builtins.elemAt (lib.splitString "/" s) 0;

  linkNames = lib.filter (
    lname:
    let
      l = links.${lname};
    in
    lib.elem nodeName (l.members or [ ]) && builtins.hasAttr nodeName (l.endpoints or { })
  ) (lib.attrNames links);

  endpoint =
    l:
    let
      ep = l.endpoints.${nodeName} or { };
      members = l.members or [ ];
      isGw = ep.gateway or false;
    in
    {
      addr4 =
        if ep ? addr4 then
          ep.addr4
        else if l.kind == "p2p" && l.vlanId <= 255 then
          addr.mkP2P4 {
            v4Base = tenantV4Base;
            vlanId = l.vlanId;
            node = nodeName;
            members = members;
          }
        else if l.kind == "lan" && isGw then
          addr.mkTenantV4 {
            v4Base = tenantV4Base;
            vlanId = l.vlanId;
          }
        else
          null;

      addr6 =
        if ep ? addr6 then
          ep.addr6
        else if l.kind == "p2p" && l.vlanId <= 255 then
          addr.mkP2P6 {
            ulaPrefix = ulaPrefix;
            vlanId = l.vlanId;
            node = nodeName;
            members = members;
          }
        else if l.kind == "lan" && isGw then
          addr.mkTenantV6 {
            ulaPrefix = ulaPrefix;
            vlanId = l.vlanId;
          }
        else
          null;

      addr6Public = ep.addr6Public or null;

      routes4 = ep.routes4 or [ ];
      routes6 = ep.routes6 or [ ];

      acceptRA = ep.acceptRA or false;
      dhcp = ep.dhcp or false;
    };

  mkRoute4 =
    r:
    {
      Destination = r.dst;
    }
    // lib.optionalAttrs (r ? via4 && r.via4 != null) {
      Gateway = r.via4;
    };

  mkRoute6 =
    r:
    {
      Destination = r.dst;
    }
    // lib.optionalAttrs (r ? via6 && r.via6 != null) {
      Gateway = r.via6;
    };

in
{
  systemd.network.networks = lib.listToAttrs (
    map (
      lname:
      let
        l = links.${lname};
        ep = endpoint l;
        isWan = (l.kind or null) == "wan";
      in
      {
        name = "50-l3-${lname}";
        value = {
          matchConfig.Name = kernelBridgeName l;

          networkConfig = {
            ConfigureWithoutCarrier = true;

            DHCP = if isWan && ep.dhcp then "yes" else "no";

            IPv6AcceptRA = if isWan then ep.acceptRA else false;

            IPv4Forwarding = true;
            IPv6Forwarding = true;

            LinkLocalAddressing = "ipv6";
          };

          addresses =
            (lib.optional (ep.addr4 != null) { Address = ep.addr4; })
            ++ (lib.optional (ep.addr6 != null) { Address = ep.addr6; })
            ++ (lib.optional (ep.addr6Public != null) { Address = ep.addr6Public; });

          routes = (map mkRoute4 ep.routes4) ++ (map mkRoute6 ep.routes6);
        };
      }
    ) linkNames
  );
}
