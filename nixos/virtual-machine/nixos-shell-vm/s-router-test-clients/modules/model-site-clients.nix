{
  builders,
  intent,
  inventory,
  lib,
  pkgs,
  siteName,
}:

let
  site = intent.esp.${siteName};

  addrPart = cidr: builtins.elemAt (lib.splitString "/" cidr) 0;
  prefixPart = cidr: builtins.elemAt (lib.splitString "/" cidr) 1;

  hasPrefix = prefix: value: lib.hasPrefix prefix value;
  removePrefix = prefix: value: lib.removePrefix prefix value;

  accessNodes = lib.filterAttrs (
    _: node:
    (node.logicalNode.site or null) == siteName
    && hasPrefix "${siteName}-router-access-" (node.logicalNode.name or "")
  ) inventory.realization.nodes;

  tenantPortNames =
    node:
    builtins.filter (name: hasPrefix "tenant-" name) (builtins.attrNames (node.ports or { }));

  tenantFromPortName = removePrefix "tenant-";

  accessTenants = lib.unique (
    map tenantFromPortName (lib.concatMap tenantPortNames (builtins.attrValues accessNodes))
  );

  accessNodeForTenant =
    tenant:
    let
      portName = "tenant-${tenant}";
      matches = builtins.filter (node: builtins.hasAttr portName (node.ports or { })) (
        builtins.attrValues accessNodes
      );
    in
    if matches == [ ] then
      throw "s-router-test-clients: no ${siteName} access node realizes tenant ${tenant}"
    else
      builtins.head matches;

  tenantRuntime =
    tenant:
    let
      node = accessNodeForTenant tenant;
      port = node.ports."tenant-${tenant}";
      iface = port.interface;
    in
    {
      bridge = port.attach.bridge;
      gw4 = addrPart iface.addr4;
      gw6 = addrPart iface.addr6;
      prefix4 = prefixPart iface.addr4;
      prefix6 = prefixPart iface.addr6;
    };

  trafficTypes = builtins.listToAttrs (
    map (trafficType: {
      name = trafficType.name;
      value = trafficType;
    }) (site.communicationContract.trafficTypes or [ ])
  );

  portsForProvider =
    provider:
    let
      providerServices = builtins.filter (service: builtins.elem provider (service.providers or [ ])) (
        site.communicationContract.services or [ ]
      );
      matches = lib.concatMap (
        service:
        let
          trafficType = trafficTypes.${service.trafficType} or { match = [ ]; };
        in
        trafficType.match or [ ]
      ) providerServices;
      portsForProto =
        proto:
        lib.unique (
          lib.concatMap (match: if (match.proto or null) == proto then match.dports or [ ] else [ ]) matches
        );
    in
    {
      tcp = portsForProto "tcp";
      udp = portsForProto "udp";
    };

  listenerModule =
    provider: ports:
    {
      networking.firewall.allowedTCPPorts = ports.tcp;
      networking.firewall.allowedUDPPorts = ports.udp;
      systemd.services =
        builtins.listToAttrs (
          map (port: {
            name = "fixture-${provider}-tcp-${toString port}";
            value = {
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:${toString port},reuseaddr,fork -";
                Restart = "always";
              };
            };
          }) ports.tcp
        )
        // builtins.listToAttrs (
          map (port: {
            name = "fixture-${provider}-udp-${toString port}";
            value = {
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                ExecStart = "${pkgs.socat}/bin/socat -u UDP-LISTEN:${toString port},reuseaddr,fork -";
                Restart = "always";
              };
            };
          }) ports.udp
        );
    };

  containerName =
    endpointName:
    if hasPrefix "${siteName}-" endpointName then endpointName else "${siteName}-${endpointName}";

  endpointContainer =
    endpoint:
    let
      runtime = tenantRuntime endpoint.tenant;
      endpointAddrs = inventory.endpoints.${endpoint.name};
      addr4 = builtins.head endpointAddrs.ipv4;
      addr6 = builtins.head endpointAddrs.ipv6;
      ports = portsForProvider endpoint.name;
      name = containerName endpoint.name;
    in
    {
      inherit name;
      value = {
        autoStart = true;
        privateNetwork = true;
        hostBridge = runtime.bridge;
        config = builders.mkStaticEndpoint {
          hostname = name;
          addr4 = "${addr4}/${runtime.prefix4}";
          gw4 = runtime.gw4;
          addr6 = "${addr6}/${runtime.prefix6}";
          gw6 = runtime.gw6;
          extraModules = lib.optional (ports.tcp != [ ] || ports.udp != [ ]) (listenerModule name ports);
        };
      };
    };

  endpointIsHostContainer =
    endpoint:
    let
      runtime = tenantRuntime endpoint.tenant;
      endpointAddrs = inventory.endpoints.${endpoint.name} or null;
    in
    endpoint.kind == "host"
    && builtins.elem endpoint.tenant accessTenants
    && endpointAddrs != null
    && builtins.head endpointAddrs.ipv4 != runtime.gw4
    && builtins.head endpointAddrs.ipv6 != runtime.gw6;
in
builtins.listToAttrs (map endpointContainer (builtins.filter endpointIsHostContainer site.ownership.endpoints))
