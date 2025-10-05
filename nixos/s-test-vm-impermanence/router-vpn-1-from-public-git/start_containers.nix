{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  inherit (lib)
    mapAttrs
    mapAttrs'
    nameValuePair
    mkMerge
    ;


    mkVpnConfigService = name: tun: secretName: pkgs.writeShellScript "write-vpn-config-${name}" ''
    set -euxo pipefail
    mkdir -p /etc/vpn/
    secret_path="${config.sops.secrets.${secretName}.path}"
    if [ -f "$secret_path" ] && [ -s "$secret_path" ]; then
      cat "$secret_path" | ${pkgs.coreutils}/bin/base64 -d > /etc/vpn/${tun}.conf
      chmod 600 /etc/vpn/${tun}.conf
    else
      echo "[ERROR] VPN config secret missing or empty: $secret_path" >&2
      exit 1
    fi
  '';


  bridges = {
    "br-ens20" = "ens20";
    "br-ens19" = "ens19";
  };

  vlanBridges = {
    "br-lan100" = {
      vlanId = 100;
      parent = "ens21";
    };
    "br-lan3001" = {
      vlanId = 3001;
      parent = "ens21";
    };
  };

  nameAirvpn = "airvpn";
  nameMullvad = "mullvad";

  enrichedVlans = mapAttrs (
    _br: cfg:
    cfg
    // {
      vlanIface = "${cfg.parent}.${toString cfg.vlanId}";
    }
  ) vlanBridges;

in
{
  ###### BRIDGES (Plain + VLAN)
  networking.bridges = mkMerge [
    (mapAttrs (br: iface: {
      interfaces = [ iface ];
    }) bridges)
    (mapAttrs (br: cfg: {
      interfaces = [ cfg.vlanIface ];
    }) enrichedVlans)
  ];

  ###### SYSCTL: Disable RA on all bridges
  boot.kernel.sysctl = mkMerge [
    (mapAttrs' (br: _: {
      name = "net.ipv6.conf.${br}.accept_ra";
      value = 0;
    }) bridges)
    (mapAttrs' (br: _: {
      name = "net.ipv6.conf.${br}.accept_ra";
      value = 0;
    }) vlanBridges)
  ];

  ###### .network configs (bridges + VLAN interfaces)
  systemd.network.networks = mkMerge [
    # Plain bridges
    (mapAttrs (br: _: {
      matchConfig.Name = br;
      linkConfig.RequiredForOnline = "no";
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
      };
    }) bridges)

    # VLAN slave interfaces (enslave to bridges)
    (mapAttrs' (
      br: cfg:
      nameValuePair cfg.vlanIface {
        matchConfig.Name = cfg.vlanIface;
        linkConfig.RequiredForOnline = "no";
        networkConfig.Bridge = br;
      }
    ) enrichedVlans)

    # VLAN bridges
    (mapAttrs' (br: _: {
      name = br;
      value = {
        matchConfig.Name = br;
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = false;
        };
      };
    }) vlanBridges)

    # Disable systemd from touching veth interfaces (e.g. lan@, wan@ from containers)
    {
      "drop-veth" = {
        matchConfig.Type = "veth";
        linkConfig.Unmanaged = true;
      };
    }
  ];

  ###### VLAN .netdev definitions
  systemd.network.netdevs = mapAttrs' (
    _br: cfg:
    nameValuePair cfg.vlanIface {
      netdevConfig = {
        Name = cfg.vlanIface;
        Kind = "vlan";
      };
      vlanConfig.Id = cfg.vlanId;
    }
  ) enrichedVlans;

  ###### CONTAINER + VPN SERVICE
  systemd.services."container@lan-to-vpn-${nameAirvpn}".serviceConfig.ConditionPathExists =
    "/etc/vpn/tun0.conf";

  containers."lan-to-vpn-${nameAirvpn}" = {
    autoStart = true;
    privateNetwork = true;

    extraVeths = {
      "wan-${nameAirvpn}" = {
        hostBridge = "br-ens19";
      };
      "lan-${nameAirvpn}" = {
        hostBridge = "br-ens20";
      };
    };

    bindMounts."/etc/vpn" = {
      hostPath = "/etc/vpn";
      isReadOnly = true;
    };

    config =
      { pkgs, config, ... }:
      {
        imports = [ inputs.nixos-router-vpn-gateway.nixosModules.default ];

        services.router-vpn-gateway = {
          enable = true;
          wanInterface = "wan-${nameAirvpn}";
          lanInterface = "lan-${nameAirvpn}";
          vpnInterface = "tun0";
          vpnProfile = "/etc/vpn/tun0.conf";
          subnets.ipv4 = "10.90.0.1/24";
          subnets.ipv6 = "fd90:dead:beef::1/64";
          dhcp4.enable = true;
          ra.enable = true;
        };
      };
  };

  ###### SOPS + VPN CONFIG


  # mullvad configuration:
  systemd.services."container@lan-to-vpn-${nameMullvad}".serviceConfig.ConditionPathExists =
    "/etc/vpn/tun1.conf";

  containers."lan-to-vpn-${nameMullvad}" = {
    autoStart = true;
    privateNetwork = true;

    extraVeths = {
      "wan-${nameMullvad}" = {
        hostBridge = "br-ens20";
      };
      "lan-${nameMullvad}" = {
        hostBridge = "br-lan3001";
      };
    };

    bindMounts."/etc/vpn" = {
      hostPath = "/etc/vpn";
      isReadOnly = true;
    };

    config =
      { pkgs, config, ... }:
      {
        imports = [ inputs.nixos-router-vpn-gateway.nixosModules.default ];

        services.router-vpn-gateway = {
          enable = true;
          wanInterface = "wan-${nameMullvad}";
          lanInterface = "lan-${nameMullvad}";
          vpnInterface = "tun1";
          vpnProfile = "/etc/vpn/tun1.conf";
          subnets.ipv4 = "10.10.0.1/24";
          subnets.ipv6 = "fd10:dead:beef::1/64";
          dhcp4.enable = true;
          ra.enable = true;
        };
      };
  };

  ###### SOPS + VPN CONFIG
  sops.secrets."vpn-lan-to-vpn-mullvad" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  systemd.services.write-vpn-config = {
    description = "Decode VPN config from sops and write to /etc/vpn/tun1.conf";
    wantedBy = [ "network-pre.target" ];
    before = [ "network-online.target" ];
    after = [ "local-fs.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkVpnConfigService nameMullvad "tun1" "vpn-lan-to-vpn-mullvad";
    };
  };
  sops.secrets."vpn-lan-to-vpn-airvpn" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  systemd.services."write-vpn-config-${nameAirvpn}" = {
  description = "Decode ${nameAirvpn} VPN config from sops and write to /etc/vpn/tun0.conf";

    wantedBy = [ "network-pre.target" ];
    before = [ "network-online.target" ];
    after = [ "local-fs.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkVpnConfigService nameAirvpn "tun0" "vpn-lan-to-vpn-airvpn";
    };
  };

}
