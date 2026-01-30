let
  lan = {
    name  = "vlan1010";
    ip4   = "10.255.255.0/29";
    iface = "br-vlan1010";
  };
in
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
            {
              name = "routers";
              data = "10.255.255.1";
            }
            {
              name = "domain-name-servers";
              data = lib.concatStringsSep "," (args.upstreamDns or [ ]);
            }
          ];
        }
      ];
    };
  };
}

