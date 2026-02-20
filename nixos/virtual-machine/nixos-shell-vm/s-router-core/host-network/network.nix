{ outPath, lib, pkgs, ... }:

let
  mkMgmt = import "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/mk-management-networkd.nix" { inherit lib pkgs; };
  mkBridge = import "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/mk-bridge-networkd.nix" { inherit lib pkgs; };
in
{
  imports = [
    (mkMgmt "eth0" 2 { bridge = "vlan2"; })

    # Upstream network (real LAN gateway lives here)
    (mkBridge "eth0" 6 { bridge = "br-upstream"; })

    # Fabric transit network (ONLY routers live here)
    (mkBridge "eth0" 200 { bridge = "br-fabric"; })
  ];
}

