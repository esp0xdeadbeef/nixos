{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.local.network.nebula-lighthouse;
  # Temporary while clients are being onboarded and mesh paths are tested.
  openFirewall = [
    {
      host = "any";
      port = "any";
      proto = "any";
    }
  ];
in
{
  options.local.network.nebula-lighthouse = {
    enable = lib.mkEnableOption "nebula lighthouse node" // {
      default = true;
    };

    networkName = lib.mkOption {
      type = lib.types.str;
      default = "mesh";
      description = "Name of the nebula network to configure.";
    };

    isRelay = lib.mkEnableOption "nebula relay role" // {
      default = true;
    };

    lighthouses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Lighthouse addresses this node should query.";
    };

    staticHostMap = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      description = "Static host map entries for the configured network.";
    };

    cert = lib.mkOption {
      type = lib.types.str;
      default = "/persist/etc/nebula/beacon.crt";
      description = "Path to the nebula node certificate.";
    };

    key = lib.mkOption {
      type = lib.types.str;
      default = "/persist/etc/nebula/beacon.key";
      description = "Path to the nebula node private key.";
    };

    ca = lib.mkOption {
      type = lib.types.str;
      default = "/persist/etc/nebula/ca.crt";
      description = "Path to the nebula CA certificate.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.nebula ];

    services.nebula.networks.${cfg.networkName} = {
      enable = true;
      isLighthouse = true;
      isRelay = cfg.isRelay;
      lighthouses = cfg.lighthouses;
      staticHostMap = cfg.staticHostMap;
      cert = cfg.cert;
      key = cfg.key;
      ca = cfg.ca;
      firewall = {
        inbound = openFirewall;
        outbound = openFirewall;
      };
    };
  };
}
