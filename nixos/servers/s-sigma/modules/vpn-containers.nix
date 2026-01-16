# vpn-containers.nix — recursion-free version

{ lib, pkgs, inputs, config, ... }:

let
  inherit (lib) mkMerge mapAttrsToList;

  # extract option value only when options are already available
  instances = config.vpn.containers.instances or {};

  perInstance = name: cfg:
    let
      wanBridge = "br-${cfg.wanInterface}";
      lanBridge = "br-${cfg.lanInterface}";
      vpnConfBasePath = "/etc/vpn";
      vpnConfPath = "${vpnConfBasePath}/${cfg.vpnProfileName}.conf";
    in mkMerge [
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

        networking.bridges.${wanBridge}.interfaces = [ cfg.wanInterface ];
        networking.bridges.${lanBridge}.interfaces = [ cfg.lanInterface ];
      }

      {
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
          config = { pkgs, config, ... }: {
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

        systemd.services."container@${name}".serviceConfig.ConditionPathExists = vpnConfPath;
      }

      {
        sops.secrets."vpn-${name}" = {
          owner = "root";
          group = "root";
          mode = "0400";
        };

        systemd.services."write-vpn-config-${name}" = {
          description = "Decode VPN config from sops and write to ${vpnConfPath}";
          wantedBy = [ "network-pre.target" ];
          before = [ "network-online.target" ];
          after = [ "local-fs.target" ];

          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "write-vpn-config-${name}" ''
              set -euxo pipefail
              mkdir -p ${vpnConfBasePath}
              secret_path="/run/secrets/vpn-${name}"
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
      }
    ];

in {
  options.vpn.containers.instances = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        enable = lib.mkEnableOption "Enable VPN container";
        wanInterface = lib.mkOption { type = lib.types.str; };
        lanInterface = lib.mkOption { type = lib.types.str; };
        vpnInterface = lib.mkOption { type = lib.types.str; };
        vpnIPv4 = lib.mkOption { type = lib.types.str; };
        vpnIPv6 = lib.mkOption { type = lib.types.str; };
        vpnProfileName = lib.mkOption { type = lib.types.str; };
      };
    });
    default = {};
    description = "Map of VPN containers by instance name";
  };

  config = mkMerge (
    mapAttrsToList (name: cfg:
      if cfg.enable then perInstance name cfg else {}
    ) instances
  );
}