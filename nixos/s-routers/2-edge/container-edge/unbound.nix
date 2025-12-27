{ pkgs, lib, ... }:
{
  services.unbound = {
    enable = true;

    settings = {
      server = {
        interface = [
          "0.0.0.0"
          "::0"
        ];
        port = 53;

        access-control = [
          "0.0.0.0/0 allow"
          "::/0 allow"
        ];

        hide-version = true;

        local-zone = [
          "lan. static"
        ];

        local-data = [
          "\"router.lan. IN A 192.168.1.1\""
          "\"nas.lan. IN A 192.168.1.10\""
          "\"nas.lan. IN AAAA fd00::10\""
        ];
      };

      forward-zone = [
        {
          name = ".";
          forward-addr = [
            "9.9.9.9#dns.quad9.net"
            "149.112.112.112#dns.quad9.net"
          ];
          forward-tls-upstream = true;
        }
      ];
    };
  };

}
