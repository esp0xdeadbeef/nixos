{ lib
, writeShellApplication
, prosafe-vlan
}:

writeShellApplication {
  name = "cobalt-switch-provision";
  runtimeInputs = [ prosafe-vlan ];
  text = ''
    exec prosafe-vlan apply -c ${../../prod-network/cobalt/switch-vlan.toml} --change-pw-allowed
  '';
  meta = with lib; {
    description = "Provision the cobalt Netgear switch VLAN configuration";
  };
}
