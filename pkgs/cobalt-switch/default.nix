{ lib
, writeShellApplication
, prosafe-vlan
, cobalt-switch-bootstrap
}:

writeShellApplication {
  name = "cobalt-switch-provision";
  runtimeInputs = [ prosafe-vlan cobalt-switch-bootstrap ];
  text = ''
    # The GS108PEv3 default-password change is JS-driven; do it via headless
    # Chromium first, then let prosafe-vlan apply the VLAN config.
    cobalt-switch-bootstrap
    exec prosafe-vlan apply -c ${../../prod-network/cobalt/switch-vlan.toml}
  '';
  meta = with lib; {
    description = "Provision the cobalt Netgear switch VLAN configuration";
  };
}
