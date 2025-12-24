{ pkgs, lib, ... }:
{

  services.unbound = {
    enable = true;

    settings = {
      server = {
        interface = [
          "127.0.0.1"
          "0.0.0.0"
          "::1"
          "::0"
        ];

        access-control = [
          "127.0.0.1 allow"
          "192.168.0.0/16 allow"
          "10.0.0.0/8 allow"
          "172.16.0.0/12 allow"
          "fd00::/8 allow"
        ];

        local-zone = [
          "lan. transparent"
          "168.192.in-addr.arpa. transparent"
        ];

      };
    };
  };

  systemd.services.unbound = {
    after = [ "kea-tsig-init.service" ];
    wants = [ "kea-tsig-init.service" ];
    serviceConfig.EnvironmentFile = "-/var/lib/kea/tsig.env";
  };
}
