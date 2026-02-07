{
  outPath,
  lib,
  pkgs,
  ...
}:

let
  mkMgmt = import "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/mk-management-networkd.nix" {
    inherit lib pkgs;
  };
  mkBridge = import "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/mk-bridge-networkd.nix" {
    inherit lib pkgs;
  };
in
{
  imports = [
    # 10-19 Management / hypervisors
    (mkBridge "lan" 10 { bridge = "lan10"; })

    # 20-29 Servers / infra
    (mkBridge "lan" 20 { bridge = "lan20"; })

    # 30-39 User LAN
    (mkBridge "lan" 30 { bridge = "lan30"; })

    # 40-49 Work / corp-segmented
    (mkBridge "lan" 40 { bridge = "lan40"; })

    # 50-59 IoT / untrusted
    (mkBridge "lan" 50 { bridge = "lan50"; })

    # 60-69 DMZ
    (mkBridge "lan" 60 { bridge = "lan60"; })

    # 70-79 Lab / exploit / test
    (mkBridge "lan" 70 { bridge = "lan70"; })

    # 80-89 Observability / monitoring
    (mkBridge "lan" 80 { bridge = "lan80"; })

    # 100-199 Transit / router links
    #(mkBridge "lan" 100 { bridge = "lan100"; })
    (mkBridge "lan" 190 { bridge = "lan100"; })

    # 1000+ WAN / ISP / upstream
    (mkBridge "lan" 1000 { bridge = "lan1000"; })

  ];
}
