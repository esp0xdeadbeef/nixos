{
  renderedHostNetwork,
  mkDmzEndpoint,
}:
if renderedHostNetwork.bridges ? dmz then
  {
    nebula01 = {
      autoStart = true;
      privateNetwork = true;
      hostBridge = "dmz";

      config = mkDmzEndpoint {
        addr4 = "10.20.30.10/24";
        gw4 = "10.20.30.1";
        addr6 = "fd42:dead:beef:30::10/64";
        gw6 = "fd42:dead:beef:30::1";
        allowedTcpPorts = [ 4242 ];
        allowedUdpPorts = [ 4242 ];
        extraModules = [
          ({ pkgs, ... }: {
            systemd.services.nebula-tcp = {
              wantedBy = [ "multi-user.target" ];
              wants = [ "network-online.target" ];
              after = [ "network-online.target" ];
              serviceConfig = {
                ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:4242,reuseaddr,fork SYSTEM:'${pkgs.coreutils}/bin/printf nebula-tcp\\n'";
                Restart = "always";
              };
            };

            systemd.services.nebula-udp = {
              wantedBy = [ "multi-user.target" ];
              wants = [ "network-online.target" ];
              after = [ "network-online.target" ];
              serviceConfig = {
                ExecStart = "${pkgs.socat}/bin/socat UDP-RECVFROM:4242,reuseaddr,fork SYSTEM:'${pkgs.coreutils}/bin/printf nebula-udp\\n'";
                Restart = "always";
              };
            };
          })
        ];
      };
    };

    wireguard01 = {
      autoStart = true;
      privateNetwork = true;
      hostBridge = "dmz";

      config = mkDmzEndpoint {
        addr4 = "10.20.30.11/24";
        gw4 = "10.20.30.1";
        addr6 = "fd42:dead:beef:30::11/64";
        gw6 = "fd42:dead:beef:30::1";
        allowedUdpPorts = [ 51820 ];
        extraModules = [
          ({ pkgs, ... }: {
            systemd.services.wireguard-udp = {
              wantedBy = [ "multi-user.target" ];
              wants = [ "network-online.target" ];
              after = [ "network-online.target" ];
              serviceConfig = {
                ExecStart = "${pkgs.socat}/bin/socat UDP-RECVFROM:51820,reuseaddr,fork SYSTEM:'${pkgs.coreutils}/bin/printf wireguard-udp\\n'";
                Restart = "always";
              };
            };
          })
        ];
      };
    };

    dmzweb01 = {
      autoStart = true;
      privateNetwork = true;
      hostBridge = "dmz";

      config = mkDmzEndpoint {
        addr4 = "10.20.30.12/24";
        gw4 = "10.20.30.1";
        addr6 = "fd42:dead:beef:30::12/64";
        gw6 = "fd42:dead:beef:30::1";
        allowedTcpPorts = [ 8080 ];
        extraModules = [
          ({ pkgs, ... }: {
            environment.etc."dmz-web/index.html".text = "dmz-web\n";
            systemd.services.dmz-web = {
              wantedBy = [ "multi-user.target" ];
              wants = [ "network-online.target" ];
              after = [ "network-online.target" ];
              serviceConfig = {
                ExecStart = "${pkgs.python3}/bin/python -m http.server 8080 --bind 0.0.0.0 --directory /etc/dmz-web";
                Restart = "always";
              };
            };
          })
        ];
      };
    };
  }
else
  { }
