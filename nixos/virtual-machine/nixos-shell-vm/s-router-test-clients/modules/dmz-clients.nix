{ builders, pkgs }:

let
  udpListener = port: "${pkgs.socat}/bin/socat -u UDP6-RECV:${toString port},fork -";

  dmzClient =
    name: address: extra:
    {
      autoStart = true;
      privateNetwork = true;
      hostBridge = "dmz";
      config = builders.mkStaticEndpoint ({
        hostname = name;
        addr4 = "${address.v4}/24";
        gw4 = "10.20.30.1";
        addr6 = "${address.v6}/64";
        gw6 = "fd42:dead:beef:30::1";
      } // extra);
    };
in
{
  nixos-nebula01 = dmzClient "nixos-nebula01" {
    v4 = "10.20.30.10";
    v6 = "fd42:dead:beef:30::10";
  } {
    extraModules = [
      {
        networking.firewall.allowedTCPPorts = [ 4242 ];
        networking.firewall.allowedUDPPorts = [ 4242 ];
        systemd.services.nebula-fixture-tcp = {
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = "${pkgs.socat}/bin/socat TCP6-LISTEN:4242,reuseaddr,fork -";
            Restart = "always";
          };
        };
        systemd.services.nebula-fixture-udp = {
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = udpListener 4242;
            Restart = "always";
          };
        };
      }
    ];
  };

  nixos-dmzweb01 = dmzClient "nixos-dmzweb01" {
    v4 = "10.20.30.12";
    v6 = "fd42:dead:beef:30::12";
  } {
    extraModules = [
      {
        environment.etc."dmz-web/index.html".text = "dmz-web\n";
        networking.firewall.allowedTCPPorts = [ 8080 ];
        systemd.services.dmz-web = {
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = "${pkgs.python3}/bin/python -m http.server 8080 --bind 0.0.0.0 --directory /etc/dmz-web";
            Restart = "always";
          };
        };
      }
    ];
  };
}
