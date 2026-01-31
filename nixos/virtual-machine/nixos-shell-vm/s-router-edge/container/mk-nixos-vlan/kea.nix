{
  pkgs,
  lib,
  helpers,
  args,
}:
{ ... }:

let
  inherit (helpers) ipv4Base3 defaultPool4 onlyIPv4;

  keaPkg = pkgs.kea;

  lans = lib.filter (l: l.dhcp4 or false) args.lans;

  upstreamV4 = onlyIPv4 (args.upstreamDns or [ ]);

  mkSubnet = l: {
    id = l.id;
    subnet = "${ipv4Base3 l.ip4}.0/${lib.last (lib.splitString "/" l.ip4)}";

    pools = [
      { pool = defaultPool4 l.ip4; }
    ];

    option-data = [
      {
        name = "routers";
        data = ipv4Base3 l.ip4 + ".1";
      }
      {
        name = "domain-name-servers";
        data = lib.concatStringsSep "," ([ (ipv4Base3 l.ip4 + ".1") ] ++ upstreamV4);
      }
      {
        name = "domain-name";
        data = args.domain or "lan.";
      }
    ];

    reservations = l.reservations or [ ];
  };

in
{
  environment.etc = lib.listToAttrs (
    map (l: {
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

          # DDNS handled by D2, no hooks in Kea 3.x
          "ddns-qualifying-suffix" = args.domain or "lan.";
          "ddns-override-client-update" = true;
          "ddns-override-no-update" = true;

          "dhcp-ddns" = {
            "enable-updates" = true;
            "server-ip" = "127.0.0.1";
            "server-port" = 53001;
          };

          subnet4 = [ (mkSubnet l) ];
        };
      };
    }) lans
  );
}
