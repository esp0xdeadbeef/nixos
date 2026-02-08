# lib/mk-l3-from-topo.nix
{ lib, pkgs }:

nodeName: topo:

let
  links = topo.links or {};

  site = import ./site-addressing.nix {};
  addr = import ./addressing.nix { inherit lib site; };

  shortHash = s: builtins.substring 0 4 (builtins.hashString "sha256" s);

  kernelBridgeName =
    l:
    let
      base =
        if (l.kind or "") == "p2p" then "br-ce"
        else if (l.kind or "") == "l2" then "br-lg"
        else "br-x";
      ident = l.name or (throw "link missing semantic name");
    in
    "${base}-${shortHash ident}";

  linkNames =
    lib.filter
      (lname:
        let l = links.${lname};
        in lib.elem nodeName (l.members or [])
           && builtins.hasAttr nodeName (l.endpoints or {})
      )
      (lib.attrNames links);

  endpoint =
    l:
      let ep = l.endpoints.${nodeName} or {};
      in ep // {
        addr4 =
          ep.addr4 or (
            if l.kind == "p2p"
            then addr.mkP2P4 { vlanId = l.vlanId; node = nodeName; members = l.members; }
            else null
          );
        addr6 =
          ep.addr6 or (
            if l.kind == "p2p"
            then addr.mkP2P6 { vlanId = l.vlanId; node = nodeName; members = l.members; }
            else null
          );
      };

in
{
  systemd.network.networks =
    lib.listToAttrs (
      map
        (lname:
          let
            l = links.${lname};
            ep = endpoint l;
          in
          {
            name = "50-l3-${lname}";
            value = {
              matchConfig.Name = kernelBridgeName l;
              networkConfig = {
                ConfigureWithoutCarrier = true;
                DHCP = "no";
                IPv6AcceptRA = false;
                IPv4Forwarding = true;
                IPv6Forwarding = true;
                LinkLocalAddressing = "ipv6";
              };
              addresses =
                (lib.optional (ep ? addr4) { Address = ep.addr4; })
                ++ (lib.optional (ep ? addr6) { Address = ep.addr6; });
              routes =
                map (r: { Destination = r.dst; Gateway = r.via4; }) (ep.routes4 or [])
                ++ map (r: { Destination = r.dst; Gateway = r.via6; }) (ep.routes6 or []);
            };
          }
        )
        linkNames
    );
}

