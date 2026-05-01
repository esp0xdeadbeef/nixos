{ builders, pkgs }:

{
  branch-node01 = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "branch";
    config = moduleArgs@{ lib, ... }:
      lib.mkMerge [
        ((builders.mkDhcpEndpoint {
          hostname = "branch-node01";
          dnsServers = [
            "10.60.10.1"
            "fd42:dead:feed:10::1"
          ];
        }) moduleArgs)
        {
          networking.firewall.enable = true;
          networking.firewall.allowedTCPPorts = [ 8081 ];
          environment.systemPackages = [ pkgs.python3 ];

          systemd.services.branch-overlay-web = {
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              ExecStart = "${pkgs.python3}/bin/python -m http.server 8081 --bind 0.0.0.0";
              Restart = "always";
            };
          };
        }
      ];
  };

  hostile-node01 = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "hostile";
    config = builders.mkDhcpEndpoint {
      hostname = "hostile-node01";
      dnsServers = [
        "10.70.10.1"
        "fd42:dead:feed:70::1"
      ];
    };
  };
}
