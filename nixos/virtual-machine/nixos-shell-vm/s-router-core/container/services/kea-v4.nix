{ pkgs, lib, ... }:

{
  environment.etc."kea/vlan1010.json".text = builtins.toJSON {
    Dhcp4 = {
      "interfaces-config" = {
        interfaces = [ "br-vlan1010" ];
      };

      "lease-database" = {
        type = "memfile";
        persist = true;
        name = "/var/lib/kea/vlan1010.leases";
      };

      subnet4 = [
        {
          id = 1010;
          subnet = "10.255.255.0/29";

          pools = [
            { pool = "10.255.255.2-10.255.255.6"; }
          ];

          option-data = [
            # Default gateway (this box)
            {
              name = "routers";
              data = "10.255.255.1";
            }

            # DNS (optional, but useful for downstream router itself)
            #{
            #  name = "domain-name-servers";
            #  data = lib.concatStringsSep "," (args.upstreamDns or [ ]);
            #}
          ];
        }
      ];
    };
  };

  systemd.services.kea-dhcp4 = {
    description = "Kea DHCPv4 (Transit br-vlan1010)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.kea}/bin/kea-dhcp4 -c /etc/kea/vlan1010.json";
      Restart = "always";
      RestartSec = 5;
    };
  };
}

