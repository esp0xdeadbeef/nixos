{ lib }:

nodeName: topo:

let
  node = topo.nodes.${nodeName} or (throw "topology: missing node '${nodeName}'");
  nodeIfs = node.ifs or (throw "topology: node '${nodeName}' missing ifs");
  links = topo.links or { };

  # Stable short hash
  shortHash = s: builtins.substring 0 4 (builtins.hashString "sha256" s);

  # Kernel-safe bridge name (<= 14 chars). Derived from *semantic* l.name.
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
        if l ? name then l.name else (throw "link missing semantic 'name' (topology.links.<x>.name)");
      h = shortHash ident;
    in
    "${base}-${h}"; # e.g. br-ce-3f2a

  # Return list of link attr names this node participates in
  linkNamesForNode = lib.filter (
    lname:
    let
      l = links.${lname};
    in
    lib.elem nodeName (l.members or [ ])
  ) (lib.attrNames links);

  # Physical carrier interface on this node
  carrierIf =
    l:
    let
      c = l.carrier or (throw "link missing carrier");
    in
    nodeIfs.${c} or (throw "node '${nodeName}' missing carrier if '${c}'");

  vlanIdStr = l: toString (l.vlanId or (throw "link missing vlanId"));
  vlanIfName = l: "${carrierIf l}.${vlanIdStr l}";

  mkVlanNetdev = l: {
    netdevConfig = {
      Name = vlanIfName l;
      Kind = "vlan";
    };
    vlanConfig.Id = lib.toInt (vlanIdStr l);
  };

  mkBridgeNetdev = l: {
    netdevConfig = {
      Name = kernelBridgeName l;
      Kind = "bridge";
    };
  };

  # Attach VLAN subif to bridge (port)
  mkPortNetwork = l: {
    matchConfig.Name = vlanIfName l;
    networkConfig = {
      DHCP = "no";
      Bridge = kernelBridgeName l;
      ConfigureWithoutCarrier = true;
    };
  };

  # Tell the physical carrier to instantiate VLAN netdev(s)
  mkCarrierNetwork = carrier: vlanIfs: {
    matchConfig.Name = carrier;
    networkConfig = {
      DHCP = "no";
      VLAN = vlanIfs;
    };
  };

  # Bridge base (L3 is applied in mk-l3-from-topo)
  carriersUsed = lib.unique (map (lname: carrierIf links.${lname}) linkNamesForNode);

  vlanIfsForCarrier =
    carrier:
    map (lname: vlanIfName links.${lname}) (
      lib.filter (lname: carrierIf links.${lname} == carrier) linkNamesForNode
    );

in
{
  systemd.network.netdevs =
    (lib.listToAttrs (
      map (lname: {
        name = "10-vlan-${lname}";
        value = mkVlanNetdev links.${lname};
      }) linkNamesForNode
    ))
    // (lib.listToAttrs (
      map (lname: {
        name = "20-bridge-${lname}";
        value = mkBridgeNetdev links.${lname};
      }) linkNamesForNode
    ));

  systemd.network.networks =
    # Create VLAN netdev(s) on each used carrier
    (lib.listToAttrs (
      map (carrier: {
        name = "10-carrier-${carrier}";
        value = mkCarrierNetwork carrier (vlanIfsForCarrier carrier);
      }) carriersUsed
    ))
    //
      # Attach VLAN subif -> bridge
      (lib.listToAttrs (
        map (lname: {
          name = "15-port-${lname}";
          value = mkPortNetwork links.${lname};
        }) linkNamesForNode
      ));
}
