{ debugPackages
, mkNebulaRuntimeService
,
}:

let
  mkNebulaRuntimeAddon =
    { nodeName
    , firewallModule ? { }
    , extraModules ? [ ]
    ,
    }:
    { ... }:
    {
      system.stateVersion = "25.11";

      imports = extraModules ++ [
        firewallModule
        (mkNebulaRuntimeService nodeName)
      ];

      systemd.network.wait-online.enable = false;
      environment.systemPackages = debugPackages.nebula;
    };

  mkNebulaNode =
    { nodeName ? "overlay-node"
    , networkModule
    , firewallModule ? { }
    , extraModules ? [ ]
    ,
    }:
    { ... }:
    {
      system.stateVersion = "25.11";

      imports = extraModules ++ [
        networkModule
        firewallModule
        (mkNebulaRuntimeService nodeName)
      ];

      networking.useNetworkd = true;
      systemd.network.enable = true;
      systemd.network.wait-online.enable = false;
      networking.useDHCP = false;
      networking.useHostResolvConf = false;
      services.resolved.enable = true;

      environment.systemPackages = debugPackages.nebula;
    };

  mkNebulaProfileMount = profileName: {
    "/persist/nebula-runtime/profiles/${profileName}" = {
      hostPath = "/persist/nebula-runtime/profiles/${profileName}";
      isReadOnly = false;
    };
    "/persist/etc/nebula" = {
      hostPath = "/persist/nebula-runtime/profiles/${profileName}";
      isReadOnly = false;
    };
    "/run/secrets/hetzner-lighthouse-public-ipv4" = {
      hostPath = "/run/secrets/hetzner-lighthouse-public-ipv4";
      isReadOnly = true;
    };
    "/run/secrets/hetzner-public-ipv6" = {
      hostPath = "/run/secrets/hetzner-public-ipv6";
      isReadOnly = true;
    };
  };
in
{
  inherit mkNebulaNode mkNebulaProfileMount mkNebulaRuntimeAddon;
}
