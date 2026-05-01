{
  mkStaticTenantEndpoint,
  mkTenantEndpoint,
}:
let
  avahiPublisher =
    serviceXml:
    {
      pkgs,
      ...
    }:
    {
      services.avahi = {
        enable = true;
        publish = {
          enable = true;
          addresses = true;
          workstation = true;
        };
      };

      environment.etc."avahi/services/runtime.service".text = serviceXml;
      environment.systemPackages = [ pkgs.avahi ];
    };
in
{
  branch-node01 = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "branch";

    config =
      {
        pkgs,
        ...
      }:
      {
        networking.hostName = "branch-node01";
        system.stateVersion = "25.11";
        networking.useNetworkd = true;
        systemd.network.enable = true;
        networking.useDHCP = false;
        networking.useHostResolvConf = false;
        services.resolved.enable = true;

        systemd.network.networks."10-eth0" = {
          matchConfig.Name = "eth0";
          networkConfig = {
            DHCP = "ipv4";
            IPv6AcceptRA = true;
            DNS = [
              "10.60.10.1"
              "fd42:dead:feed:10::1"
            ];
            Domains = [ "lan." ];
          };
        };

        environment.systemPackages = [
          pkgs.bind
          pkgs.curl
          pkgs.iproute2
          pkgs.iputils
          pkgs.python3
          pkgs.traceroute
        ];

        networking.firewall.enable = true;
        networking.firewall.allowedTCPPorts = [ 8081 ];

        systemd.services.branch-overlay-web = {
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = "${pkgs.python3}/bin/python -m http.server 8081 --bind 0.0.0.0";
            Restart = "always";
          };
        };
      };
  };

  hostile-node01 = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "hostile";

    config =
      {
        pkgs,
        ...
      }:
      {
        networking.hostName = "hostile-node01";
        system.stateVersion = "25.11";
        networking.useNetworkd = true;
        systemd.network.enable = true;
        networking.useDHCP = false;
        networking.useHostResolvConf = false;
        services.resolved.enable = true;

        systemd.network.networks."10-eth0" = {
          matchConfig.Name = "eth0";
          networkConfig = {
            DHCP = "ipv4";
            IPv6AcceptRA = true;
            DNS = [
              "10.70.10.1"
              "fd42:dead:feed:70::1"
            ];
            Domains = [ "lan." ];
          };
        };

        environment.systemPackages = [
          pkgs.bind
          pkgs.curl
          pkgs.iproute2
          pkgs.iputils
          pkgs.traceroute
        ];
      };
  };

  admin-test = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "admin";

    config = mkTenantEndpoint "admin";
  };

  client-test = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "client";

    config = mkTenantEndpoint "client";
  };

  client2-test = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "client2";

    config = mkTenantEndpoint "client2";
  };

  mgmt-test = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "mgmt";

    config = mkTenantEndpoint "mgmt";
  };

  sigma-site-c = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "site-c-mgmt";

    config = mkStaticTenantEndpoint {
      hostname = "sigma-site-c";
      addr4 = "10.90.10.10/24";
      gw4 = "10.90.10.1";
      addr6 = "fd42:dead:cafe:10::10/64";
      gw6 = "fd42:dead:cafe:10::1";
      dnsServers = [
        "10.90.10.1"
        "fd42:dead:cafe:10::1"
      ];
    };
  };

  home-user-01 = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "home-users";

    config = mkStaticTenantEndpoint {
      hostname = "home-user-01";
      addr4 = "10.90.20.10/24";
      gw4 = "10.90.20.1";
      addr6 = "fd42:dead:cafe:20::10/64";
      gw6 = "fd42:dead:cafe:20::1";
      mdnsClient = true;
      dnsServers = [
        "10.90.20.1"
        "fd42:dead:cafe:20::1"
      ];
    };
  };

  test-machine-01 = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "printer";

    config = mkStaticTenantEndpoint {
      hostname = "test-machine-01";
      addr4 = "10.90.30.2/29";
      gw4 = "10.90.30.1";
      addr6 = "fd42:dead:cafe:30::10/64";
      gw6 = "fd42:dead:cafe:30::1";
      dnsServers = [
        "10.90.30.1"
        "fd42:dead:cafe:30::1"
      ];
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
  };

  streaming-cast-01 = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "streaming";

    config = mkStaticTenantEndpoint {
      hostname = "streaming-cast-01";
      addr4 = "10.90.50.2/29";
      gw4 = "10.90.50.1";
      addr6 = "fd42:dead:cafe:50::10/64";
      gw6 = "fd42:dead:cafe:50::1";
      dnsServers = [
        "10.90.50.1"
        "fd42:dead:cafe:50::1"
      ];
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
        ({
          pkgs,
          lib,
          ...
        }:
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
          })
      ];
    };
  };
}
