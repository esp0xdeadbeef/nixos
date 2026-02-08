# lib/mk-l3-from-topo.nix
{ lib, pkgs }:

nodeName: topo:

let
  links = topo.links or { };

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
      ident =
        if l ? name then
          l.name
        else
          throw "link missing semantic 'name' (topology.links.<x>.name)";
      h = shortHash ident;
    in
    "${base}-${h}";

  # Links where node participates AND has endpoint intent
  linkNames = lib.filter (
    lname:
    let
      l = links.${lname};
    in
    lib.elem nodeName (l.members or [ ]) && (builtins.hasAttr nodeName (l.endpoints or { }))
  ) (lib.attrNames links);

  endpoint = l: l.endpoints.${nodeName};

  baseNetwork = l: {
    matchConfig.Name = kernelBridgeName l;
    networkConfig = {
      ConfigureWithoutCarrier = true;
      DHCP = "no";
      IPv6AcceptRA = false;

      IPv4Forwarding = true;
      IPv6Forwarding = true;

      LinkLocalAddressing = "ipv6";
    };
  };

  addrEntries =
    ep:
    (lib.optional (ep ? addr4) { Address = ep.addr4; })
    ++ (lib.optional (ep ? addr6) { Address = ep.addr6; });

  routeEntries4 =
    ep:
    map (r: {
      Destination = r.dst;
      Gateway = r.via4;
    }) (ep.routes4 or [ ]);

  routeEntries6 =
    ep:
    map (r: {
      Destination = r.dst;
      Gateway = r.via6;
    }) (ep.routes6 or [ ]);

  mkOneshot = name: scriptText: {
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-networkd.service" ];
    requires = [ "systemd-networkd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript name scriptText;
    };
  };

  prefixRouteSvc =
    lname: l:
    let
      ep = endpoint l;
      cfg = ep.route6FromPrefixFile or null;
    in
    lib.mkIf (cfg != null) {
      "fabric-route6-${lname}" = mkOneshot "fabric-route6-${lname}" ''
        set -euo pipefail
        IF="${kernelBridgeName l}"
        FILE="${cfg.prefixFile}"
        GW="${cfg.via6}"

        for i in $(seq 1 80); do
          ${pkgs.iproute2}/bin/ip link show "$IF" >/dev/null 2>&1 && break
          sleep 0.25
        done

        PREFIX="$(tr -d ' \t\r\n' < "$FILE")"
        ${pkgs.iproute2}/bin/ip -6 route replace "$PREFIX" via "$GW" dev "$IF"
      '';
    };

in
{
  # ONE .network per bridge: base + addresses + routes
  systemd.network.networks =
    lib.listToAttrs (
      map (
        lname:
        let
          l = links.${lname};
          ep = endpoint l;
        in
        {
          name = "50-l3-${lname}";
          value =
            (baseNetwork l)
            // {
              addresses = addrEntries ep;
              routes = (routeEntries4 ep) ++ (routeEntries6 ep);
            };
        }
      ) linkNames
    );

  systemd.services =
    lib.foldl' (
      acc: lname:
      let
        l = links.${lname};
      in
      acc // (prefixRouteSvc lname l)
    ) { } linkNames;

  boot.kernel.sysctl =
    lib.foldl' (
      acc: lname:
      let
        l = links.${lname};
        ifn = kernelBridgeName l;
      in
      acc
      // {
        "net.ipv6.conf.${ifn}.accept_ra" = 0;
        "net.ipv6.conf.${ifn}.autoconf" = 0;
        "net.ipv6.conf.${ifn}.use_tempaddr" = lib.mkForce 0;
        "net.ipv6.conf.${ifn}.forwarding" = 1;
        "net.ipv4.conf.${ifn}.forwarding" = 1;
      }
    ) { } linkNames;

  assertions = [
    {
      assertion = linkNames != [ ];
      message =
        "mk-l3-from-topo: no L3 links matched for node '${nodeName}'. "
        + "Check topology.nodes and topology.links.<x>.endpoints.";
    }
  ];
}

