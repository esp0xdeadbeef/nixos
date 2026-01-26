{ pkgs, lib, helpers, args }:
{ ... }:

let
  inherit (helpers) ipv4Base3 defaultPool4;

  lans = lib.filter (l: l.dhcp4 or false) args.lans;

  mkSubnet = l: {
    id = l.id or (builtins.fromJSON (toString (builtins.length l.name)));
    subnet = "${ipv4Base3 l.ip4}.0/${lib.last (lib.splitString "/" l.ip4)}";
    pools = [ { pool = defaultPool4 l.ip4; } ];

    option-data = [
      # default gateway (DHCP option 3)
      {
        name = "routers";
        data = ipv4Base3 l.ip4 + ".1";
      }

      # DNS
      {
        name = "domain-name-servers";
        data = lib.concatStringsSep "," (args.upstreamDns or []);
      }

      {
        name = "domain-name";
        data = args.domain or "lan.";
      }
    ];
  };
in
{
  environment.etc =
    lib.listToAttrs (map (l: {
      name = "kea/${l.name}.json";
      value.text = builtins.toJSON {
        Dhcp4 = {
          "interfaces-config" = {
            interfaces = [ l.iface ];
          };

          "lease-database" = {
            type = "memfile";
            persist = true;
            name = "/var/lib/kea/${l.name}.leases";
          };

          subnet4 = [ (mkSubnet l) ];
        };
      };
    }) lans);
}

