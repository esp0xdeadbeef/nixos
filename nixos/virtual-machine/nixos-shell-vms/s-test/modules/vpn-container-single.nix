{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:

let
  cfg = config.vpn.container;

  wanBridge = "br-${cfg.wanInterface}";
  lanBridge = "br-${cfg.lanInterface}";

  vpnConfBasePath = "/etc/vpn";
  vpnConfPath = "${vpnConfBasePath}/${cfg.vpnProfileName}.conf";
in
{
  options.vpn.container = {
    enable = lib.mkEnableOption "Enable VPN container";

    name = lib.mkOption {
      type = lib.types.str;
      description = "Container name";
    };

    wanInterface = lib.mkOption {
      type = lib.types.str;
      description = "Physical WAN interface to bridge";
    };

    lanInterface = lib.mkOption {
      type = lib.types.str;
      description = "Physical LAN interface to bridge";
    };

    vpnInterface = lib.mkOption {
      type = lib.types.str;
      description = "VPN tunnel device";
    };

    vpnIPv4 = lib.mkOption {
      type = lib.types.str;
      description = "VPN IPv4 subnet";
    };

    vpnIPv6 = lib.mkOption {
      type = lib.types.str;
      description = "VPN IPv6 subnet";
    };

    vpnProfileName = lib.mkOption {
      type = lib.types.str;
      description = "Name of the secret config (used for SOPS and file path)";
    };
  };

  config = lib.mkIf cfg.enable {
    # sysctl
    boot.kernel.sysctl = {
      "net.ipv6.conf.${wanBridge}.accept_ra" = 0;
      "net.ipv6.conf.${lanBridge}.accept_ra" = 0;
    };

    systemd.network.networks."${wanBridge}" = {
      matchConfig.Name = "${wanBridge}";
      linkConfig.RequiredForOnline = "no";
      networkConfig.DHCP = "no";
      networkConfig.IPv6AcceptRA = false;
    };

    systemd.network.networks."${lanBridge}" = {
      matchConfig.Name = lanBridge;
      linkConfig.RequiredForOnline = "no";
      networkConfig.DHCP = "no";
      networkConfig.IPv6AcceptRA = false;
    };

    # create bridges automatically
    networking.bridges.${wanBridge}.interfaces = [ cfg.wanInterface ];
    networking.bridges.${lanBridge}.interfaces = [ cfg.lanInterface ];

    # container
    containers."${cfg.name}" = {
      autoStart = true;
      privateNetwork = true;

      extraVeths = {
        wan.hostBridge = wanBridge;
        lan.hostBridge = lanBridge;
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
            wanInterface = "wan";
            lanInterface = "lan";
            vpnInterface = cfg.vpnInterface;
            vpnProfile = vpnConfPath;
            subnets.ipv4 = cfg.vpnIPv4;
            subnets.ipv6 = cfg.vpnIPv6;
            dhcp4.enable = true;
            ra.enable = true;
          };
        };
    };

    # sops secret
    sops.secrets."vpn-${cfg.name}" = {
      owner = "root";
      group = "root";
      mode = "0400";
    };

    # write vpn config file from secret
    systemd.services."write-vpn-config-${cfg.name}" = {
      description = "Decode VPN config from sops and write to ${vpnConfPath}";
      wantedBy = [ "network-pre.target" ];
      before = [ "network-online.target" ];
      after = [ "local-fs.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "write-vpn-config-${cfg.name}" ''
          set -euxo pipefail
          mkdir -p ${vpnConfBasePath}
          secret_path="${config.sops.secrets."vpn-${cfg.name}".path}"
          if [ -f "$secret_path" ] && [ -s "$secret_path" ]; then
            cat "$secret_path" | ${pkgs.coreutils}/bin/base64 -d > ${vpnConfPath}
            chmod 600 ${vpnConfPath}
          else
            echo "[ERROR] VPN config secret missing or empty: $secret_path" >&2
            exit 1
          fi
        '';
      };
    };

    # container service only starts if vpn config exists
    systemd.services."container@${cfg.name}".serviceConfig.ConditionPathExists = vpnConfPath;
  };
}
