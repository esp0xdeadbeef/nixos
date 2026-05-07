{
  debugPackages,
  mkNebulaRuntimeService,
}:

let
  mkNebulaRuntimeAddon =
    {
      nodeName,
      firewallModule ? { },
      extraModules ? [ ],
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
    {
      nodeName ? "overlay-node",
      networkModule,
      firewallModule ? { },
      extraModules ? [ ],
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
    "/persist/etc/nebula" = {
      hostPath = "/persist/nebula-runtime/profiles/${profileName}";
      isReadOnly = false;
    };
  };
in
{
  inherit mkNebulaNode mkNebulaProfileMount mkNebulaRuntimeAddon;
}
