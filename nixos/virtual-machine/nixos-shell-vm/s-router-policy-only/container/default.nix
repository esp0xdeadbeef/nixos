{
  outPath,
  lib,
  pkgs,
  controlPlaneOut,
  ...
}:

let
  inventory = import ../inventory.nix { inherit lib outPath; };

  hostName = "s-router-policy-only";

  nodeName =
    let
      nodeNames = builtins.attrNames inventory.realization.nodes;
      matches = lib.filter (n: inventory.realization.nodes.${n}.host == hostName) nodeNames;
    in
    if matches == [ ] then
      abort "container/default.nix: no realization node found for host '${hostName}'"
    else if builtins.length matches > 1 then
      abort "container/default.nix: multiple realization nodes found for host '${hostName}': ${lib.concatStringsSep ", " matches}"
    else
      builtins.head matches;

  cpm = controlPlaneOut;

  enterpriseNames = builtins.attrNames cpm.enterprise;
  enterpriseName =
    if enterpriseNames == [ ] then
      abort "container/default.nix: controlPlaneOut.enterprise is empty"
    else if builtins.length enterpriseNames > 1 then
      abort "container/default.nix: multiple enterprises in controlPlaneOut: ${lib.concatStringsSep ", " enterpriseNames}"
    else
      builtins.head enterpriseNames;

  siteNames = builtins.attrNames cpm.enterprise.${enterpriseName}.site;
  siteName =
    if siteNames == [ ] then
      abort "container/default.nix: controlPlaneOut.enterprise.${enterpriseName}.site is empty"
    else if builtins.length siteNames > 1 then
      abort "container/default.nix: multiple sites in controlPlaneOut.enterprise.${enterpriseName}.site: ${lib.concatStringsSep ", " siteNames}"
    else
      builtins.head siteNames;

  site = cpm.enterprise.${enterpriseName}.site.${siteName};

  node =
    if site ? nodes && builtins.hasAttr nodeName site.nodes then
      site.nodes.${nodeName}
    else
      abort "container/default.nix: controlPlaneOut.enterprise.${enterpriseName}.site.${siteName}.nodes.${nodeName} is missing";

  realizedPorts = inventory.realization.nodes.${nodeName}.ports;

  topoIfForPort =
    port:
    let
      matches = lib.filterAttrs (_: v: (v.link or null) == port.link) node.interfaces;
      names = builtins.attrNames matches;
    in
    if names == [ ] then
      abort "container/default.nix: no topology interface for port link '${port.link}'"
    else if builtins.length names > 1 then
      abort "container/default.nix: multiple topology interfaces for port link '${port.link}': ${lib.concatStringsSep ", " names}"
    else
      builtins.head names;

  routesFor =
    family: rs:
    map (
      r:
      let
        dst =
          if family == "ipv4" then
            (r.dst or null)
          else if (r.dst or null) == "0000:0000:0000:0000:0000:0000:0000:0000/0" then
            "::/0"
          else
            (r.dst or null);
      in
      { Destination = dst; }
      // lib.optionalAttrs (r ? via4) { Gateway = r.via4; }
      // lib.optionalAttrs (r ? via6) { Gateway = r.via6; }
    ) (
      lib.filter (
        r:
        let
          proto = r.proto or "";
          dst =
            if family == "ipv4" then
              (r.dst or null)
            else if (r.dst or null) == "0000:0000:0000:0000:0000:0000:0000:0000/0" then
              "::/0"
            else
              (r.dst or null);
        in
        dst != null && !(builtins.elem proto [ "connected" "internal" ])
      ) rs
    );

  networkForPort =
    portName:
    let
      port = realizedPorts.${portName};
      topoIfName = topoIfForPort port;
      topoIf = node.interfaces.${topoIfName};

      v4Routes = routesFor "ipv4" (topoIf.routes.ipv4 or [ ]);
      v6Routes = routesFor "ipv6" (topoIf.routes.ipv6 or [ ]);
    in
    {
      matchConfig.Name = port.interface.name;

      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
        IPv4Forwarding = true;
        IPv6Forwarding = true;
        ConfigureWithoutCarrier = true;
      };

      linkConfig.RequiredForOnline = false;

      addresses =
        (lib.optional (topoIf ? addr4) { Address = topoIf.addr4; })
        ++ (lib.optional (topoIf ? addr6) { Address = topoIf.addr6; });

      routes = v4Routes ++ v6Routes;
    };

  renderedNetworks = builtins.listToAttrs (
    map (portName: {
      name = "10-${portName}";
      value = networkForPort portName;
    }) (builtins.attrNames realizedPorts)
  );
in
{
  imports = [
    ./debugging-packages.nix
  ];

  networking.hostName = nodeName;

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;
  networking.networkmanager.enable = false;
  networking.useHostResolvConf = false;

  networking.firewall.enable = false;
  services.resolved.enable = false;

  boot.isContainer = true;

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = lib.mkDefault 1;
    "net.ipv6.conf.all.forwarding" = lib.mkDefault 1;
    "net.ipv6.conf.default.forwarding" = lib.mkDefault 1;
  };

  systemd.network.networks = lib.mkForce renderedNetworks;

  system.stateVersion = "25.11";
}
