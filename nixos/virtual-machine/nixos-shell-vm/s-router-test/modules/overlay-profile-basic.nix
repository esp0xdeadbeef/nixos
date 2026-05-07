{ networkModules }:

{
  coreClient = {
    networkModule = networkModules.dhcp;
    firewallModule.networking.firewall.enable = true;
  };

  branchWeb = {
    networkModule = networkModules.dhcp;
    firewallModule = {
      networking.firewall.enable = true;
      networking.firewall.interfaces.nebula1.allowedTCPPorts = [ 8081 ];
    };
    extraModules = [
      ({ pkgs, ... }: {
        systemd.services.branch-overlay-web = {
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = "${pkgs.python3}/bin/python -m http.server 8081 --bind 0.0.0.0";
            Restart = "always";
          };
        };
      })
    ];
  };

  storageClient = {
    networkModule = networkModules.dhcp;
    firewallModule.networking.firewall.enable = true;
  };

  coreRouterNebula = {
    inPlace = true;
    firewallModule.networking.firewall.enable = true;
  };
}
