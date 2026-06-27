{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  inherit (lib)
    mkOption
    types
    mkEnableOption
    mapAttrsToList
    mkIf
    mkMerge
    ;

  cfg = config.vpn.containers;
in
{
  options.vpn.containers = {
    enable = mkEnableOption "Enable VPN container generation";

    trunkInterface = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional trunk interface (e.g., ens21)";
    };

    instances = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            vlan.wan = mkOption {
              type = types.nullOr types.int;
              default = null;
              description = "WAN VLAN ID (optional)";
            };

            uplinkInterface = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Uplink interface (optional)";
            };

            lanBridge = mkOption {
              type = types.str;
              description = "LAN bridge to attach to";
            };
          };
        }
      );
      default = { };
      description = "VPN container instance configurations";
    };
  };

  config = mkIf cfg.enable {
    containers = mkMerge (
      mapAttrsToList (
        name: spec:
        let
          wanInterface =
            if spec.vlan.wan != null && cfg.trunkInterface != null then
              "${cfg.trunkInterface}.${toString spec.vlan.wan}"
            else if spec.uplinkInterface != null then
              spec.uplinkInterface
            else
              throw "vpn.containers.instances.${name} requires either vlan.wan + trunkInterface or uplinkInterface";

          lanInterface = "lan"; # always static
          wanInterfaceName = "wan"; # always static

          vpnInterface = "tun0";
          vpnIPv4WithMask = "10.90.0.1/24";
          vpnIPv6WithMask = "fd90:dead:beef::1/64";
          vpnConfBasePath = "/etc/vpn";
          vpnConfPath = "${vpnConfBasePath}/${vpnInterface}.conf";
        in
        {
          ${name} = {
            autoStart = true;
            privateNetwork = true;

            extraVeths = {
              ${wanInterfaceName}.hostBridge = wanInterface;
              ${lanInterface}.hostBridge = spec.lanBridge;
            };

            bindMounts."/etc/vpn" = {
              hostPath = "/etc/vpn";
              isReadOnly = true;
            };

            config =
              { config, pkgs, ... }:
              {
                imports = [ inputs.nixos-router-vpn-gateway.nixosModules.default ];

                services.router-vpn-gateway = {
                  enable = true;
                  wanInterface = wanInterfaceName;
                  lanInterface = lanInterface;
                  vpnInterface = vpnInterface;
                  vpnProfile = vpnConfPath;
                  subnets.ipv4 = vpnIPv4WithMask;
                  subnets.ipv6 = vpnIPv6WithMask;
                  dhcp4.enable = true;
                  ra.enable = true;
                };
              };
          };
        }
      ) cfg.instances
    );
  };
}
