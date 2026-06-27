{ lib, ... }:

let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.vpn.containers.instances = mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          enable = mkEnableOption "Enable this VPN container";

          wanInterface = mkOption { type = types.str; };
          lanInterface = mkOption { type = types.str; };
          vpnInterface = mkOption { type = types.str; };
          vpnIPv4 = mkOption { type = types.str; };
          vpnIPv6 = mkOption { type = types.str; };
          vpnProfileName = mkOption { type = types.str; };
        };
      }
    );

    default = { };
    description = "VPN container configurations keyed by container name.";
  };
}
