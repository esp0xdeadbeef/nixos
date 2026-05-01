{ builders, lib, pkgs }:

let
  avahiPublisher = import ./avahi-service.nix { inherit pkgs; };

  staticClient =
    name: bridge: args:
    {
      autoStart = true;
      privateNetwork = true;
      hostBridge = bridge;
      config = builders.mkStaticEndpoint ({ hostname = name; } // args);
    };
in
{
  sigma-site-c = staticClient "sigma-site-c" "site-c-mgmt" {
    addr4 = "10.90.10.10/24";
    gw4 = "10.90.10.1";
    addr6 = "fd42:dead:cafe:10::10/64";
    gw6 = "fd42:dead:cafe:10::1";
  };

  home-user-01 = staticClient "home-user-01" "home-users" {
    addr4 = "10.90.20.10/24";
    gw4 = "10.90.20.1";
    addr6 = "fd42:dead:cafe:20::10/64";
    gw6 = "fd42:dead:cafe:20::1";
    mdnsClient = true;
  };

  test-machine-01 = staticClient "test-machine-01" "printer" {
    addr4 = "10.90.30.2/29";
    gw4 = "10.90.30.1";
    addr6 = "fd42:dead:cafe:30::10/64";
    gw6 = "fd42:dead:cafe:30::1";
    extraModules = [
      (avahiPublisher ''
        <?xml version="1.0" standalone='no'?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">%h</name>
          <service>
            <type>_printer._tcp</type>
            <port>9100</port>
          </service>
        </service-group>
      '')
    ];
  };

  printer-node01 = staticClient "printer-node01" "printer" {
    addr4 = "10.90.30.3/29";
    gw4 = "10.90.30.1";
    addr6 = "fd42:dead:cafe:30::20/64";
    gw6 = "fd42:dead:cafe:30::1";
    extraModules = [
      (avahiPublisher ''
        <?xml version="1.0" standalone='no'?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">%h</name>
          <service>
            <type>_printer._tcp</type>
            <port>9100</port>
          </service>
        </service-group>
      '')
    ];
  };

  nas-node01 = staticClient "nas-node01" "nas" {
    addr4 = "10.90.40.2/29";
    gw4 = "10.90.40.1";
    addr6 = "fd42:dead:cafe:40::10/64";
    gw6 = "fd42:dead:cafe:40::1";
  };

  streaming-cast-01 = staticClient "streaming-cast-01" "streaming" {
    addr4 = "10.90.50.2/29";
    gw4 = "10.90.50.1";
    addr6 = "fd42:dead:cafe:50::10/64";
    gw6 = "fd42:dead:cafe:50::1";
    extraModules = [
      (avahiPublisher ''
        <?xml version="1.0" standalone='no'?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">%h</name>
          <service>
            <type>_googlecast._tcp</type>
            <port>8009</port>
            <txt-record>fn=streaming-cast-01</txt-record>
            <txt-record>md=Chromecast</txt-record>
          </service>
        </service-group>
      '')
      {
        networking.firewall.allowedTCPPorts = lib.mkAfter [ 8009 ];
        systemd.sockets.fake-googlecast = {
          wantedBy = [ "sockets.target" ];
          listenStreams = [ "[::]:8009" ];
          socketConfig = {
            Accept = true;
            BindIPv6Only = "both";
          };
        };
        systemd.services."fake-googlecast@" = {
          serviceConfig = {
            StandardInput = "socket";
            ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/cat >/dev/null'";
          };
        };
      }
    ];
  };
}
