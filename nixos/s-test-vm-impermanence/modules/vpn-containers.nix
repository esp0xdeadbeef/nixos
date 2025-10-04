# modules/vpn-containers.nix
{ lib, config, pkgs, inputs, ... }:

with lib;

let
  cfg = config.vpn.containers;
  
  instanceModule = { name, config, ... }: {
    options = {
      wanInterface = mkOption {
        type = types.str;
        description = "Physical WAN interface to bridge (can be VLAN).";
      };

      lanInterface = mkOption {
        type = types.str;
        description = "Physical LAN interface to bridge (can be VLAN).";
      };

      vpnInterface = mkOption {
        type = types.str;
        description = "VPN tunnel device.";
      };

      vpnIPv4 = mkOption {
        type = types.str;
        description = "VPN IPv4 subnet.";
      };

      vpnIPv6 = mkOption {
        type = types.str;
        description = "VPN IPv6 subnet.";
      };

      vpnProfileName = mkOption {
        type = types.str;
        description = "Name of the secret config (used for SOPS and file path).";
      };
    };
  };

in {
  options.vpn.containers = {
    enable = mkEnableOption "Enable multiple VPN containers";

    instances = mkOption {
      type = types.attrsOf (types.submodule instanceModule);
      default = {};
      description = "VPN container instances.";
    };
  };

  config = mkIf cfg.enable (mkMerge (
    mapAttrsToList (name: instCfg:
      let
        wanBridge = "br-${instCfg.wanInterface}";
        lanBridge = "br-${instCfg.lanInterface}";
        vpnConfBasePath = "/etc/vpn";
        vpnConfPath = "${vpnConfBasePath}/${instCfg.vpnProfileName}.conf";
      in
      {
        boot.kernel.sysctl = {
          "net.ipv6.conf.${wanBridge}.accept_ra" = 0;
          "net.ipv6.conf.${lanBridge}.accept_ra" = 0;
        };

        systemd.network.networks.${wanBridge} = {
          matchConfig.Name = wanBridge;
          linkConfig.RequiredForOnline = "no";
          networkConfig.DHCP = "no";
          networkConfig.IPv6AcceptRA = false;
        };

        systemd.network.networks.${lanBridge} = {
          matchConfig.Name = lanBridge;
          linkConfig.RequiredForOnline = "no";
          networkConfig.DHCP = "no";
          networkConfig.IPv6AcceptRA = false;
        };

        networking.bridges.${wanBridge}.interfaces = [ instCfg.wanInterface ];
        networking.bridges.${lanBridge}.interfaces = [ instCfg.lanInterface ];

        containers.${name} = {
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

          config = { config, pkgs, ... }: {
            imports = [ inputs.nixos-router-vpn-gateway.nixosModules.default ];

            services.router-vpn-gateway = {
              enable = true;
              wanInterface = "wan";
              lanInterface = "lan";
              vpnInterface = instCfg.vpnInterface;
              vpnProfile = vpnConfPath;
              subnets.ipv4 = instCfg.vpnIPv4;
              subnets.ipv6 = instCfg.vpnIPv6;
              dhcp4.enable = true;
              ra.enable = true;
            };
          };
        };

        sops.secrets."vpn-${name}" = {
          owner = "root";
          group = "root";
          mode = "0400";
        };

        systemd.services."write-vpn-config-${name}" = {
          description = "Decode VPN config for ${name}";
          wantedBy = [ "network-pre.target" ];
          before = [ "network-online.target" ];
          after = [ "local-fs.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "write-vpn-config-${name}" ''
              set -euxo pipefail
              mkdir -p ${vpnConfBasePath}
              secret_path="${config.sops.secrets."vpn-${name}".path}"
              if [ -f "$secret_path" ] && [ -s "$secret_path" ]; then
                cat "$secret_path" | ${pkgs.coreutils}/bin/base64 -d > ${vpnConfPath}
                chmod 600 ${vpnConfPath}
              else
                echo "[ERROR] Missing VPN config: $secret_path" >&2
                exit 1
              fi
            '';
          };
        };

        systemd.services."container@${name}".serviceConfig.ConditionPathExists = vpnConfPath;
      }
    ) cfg.instances
  ));
}