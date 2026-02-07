# library/1010-router-legacy-edge/default.nix
{ lib, config, ... }:

let
  # === HARD CONSTANTS ===
  vlanId = 1010;
  vlanIf = "lan.${toString vlanId}";
  bridgeIf = "br-vlan${toString vlanId}";
  legacyAddrV4 = "10.255.255.1/29";

  netdevs = config.systemd.network.netdevs or { };
  networks = config.systemd.network.networks or { };

  # --- helpers ---
  any = lib.any;
  attrValues = builtins.attrValues;

  # VLAN interface exists
  vlanIfExists = any (
    d:
    (d.netdevConfig.Kind or null) == "vlan"
    && (d.netdevConfig.Name or null) == vlanIf
    && (d.vlanConfig.Id or null) == vlanId
  ) (attrValues netdevs);

  # Bridge exists
  bridgeExists = any (
    d: (d.netdevConfig.Kind or null) == "bridge" && (d.netdevConfig.Name or null) == bridgeIf
  ) (attrValues netdevs);

  # VLAN enslaved into bridge
  vlanEnslaved = any (
    n: (n.matchConfig.Name or null) == vlanIf && (n.networkConfig.Bridge or null) == bridgeIf
  ) (attrValues networks);

  # Bridge network exists
  bridgeNetworkExists = any (n: (n.matchConfig.Name or null) == bridgeIf) (attrValues networks);

  # IPv4 /29 address assigned to bridge
  ipv4AddrExists = any (
    n:
    (n.matchConfig.Name or null) == bridgeIf && any (a: a.Address == legacyAddrV4) (n.addresses or [ ])
  ) (attrValues networks);

in
{
  assertions = [
    {
      assertion = vlanIfExists;
      message = ''
        🚨 LEGACY EDGE INVARIANT VIOLATION 🚨
        Missing VLAN interface: ${vlanIf}
        VLAN ${toString vlanId} MUST exist and MUST be created via systemd-networkd.
      '';
    }

    {
      assertion = bridgeExists;
      message = ''
        🚨 LEGACY EDGE INVARIANT VIOLATION 🚨
        Missing bridge: ${bridgeIf}
        Legacy router edge requires a dedicated bridge.
      '';
    }

    {
      assertion = vlanEnslaved;
      message = ''
        🚨 LEGACY EDGE INVARIANT VIOLATION 🚨
        ${vlanIf} is NOT enslaved into ${bridgeIf}.
        This breaks the legacy L2/L3 handoff.
      '';
    }

    {
      assertion = bridgeNetworkExists;
      message = ''
        🚨 LEGACY EDGE INVARIANT VIOLATION 🚨
        ${bridgeIf} has no systemd-networkd network section.
        Bridge must be explicitly managed.
      '';
    }

    {
      assertion = ipv4AddrExists;
      message = ''
        🚨 LEGACY EDGE INVARIANT VIOLATION 🚨
        IPv4 address ${legacyAddrV4} is NOT assigned to ${bridgeIf}.
        Kea DHCPv4 and legacy routing WILL BREAK.
      '';
    }
  ];
}
