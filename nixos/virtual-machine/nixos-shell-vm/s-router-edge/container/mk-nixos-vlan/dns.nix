{ config, pkgs, lib, args, helpers, ... }:

let
  lans = args.lans or [ ];

  # Normalize domain to FQDN with trailing dot
  domainRaw = args.domain or "lan.";
  domain =
    if lib.hasSuffix "." domainRaw then domainRaw else "${domainRaw}.";

  # IPv4 forward ACLs (assume /24 like your design)
  v4Nets = map (l:
    let base = helpers.ipv4Base3 l.ip4;
    in "${base}.0/24"
  ) lans;

  # Reverse zones derived from LAN IPv4 (/24 only)
  reverseZonesV4 =
    map (l: helpers.reverseZoneV4_24 l.ip4) lans;

  # Upstream recursive resolvers
  upstream = args.upstreamDns or [ ];

  # Flatten all DHCP reservations from all LANs
  reservations =
    lib.flatten (map (l: l.reservations or [ ]) lans);

  fqdn =
    h:
    if lib.hasSuffix "." h then h else "${h}.${domain}";

  # A records from reservations
  #   local-data: "printer2.lan. A 10.13.37.21"
localDataA =
  map (r: "\"${fqdn r.hostname} A ${r.ip-address}\"") reservations;


  # PTR records from reservations
  #   local-data-ptr: "10.13.37.21 printer2.lan."
localDataPtr =
  map (r: "\"${r.ip-address} ${fqdn r.hostname}\"") reservations;


in
{
  # Hard kill BIND if it ever sneaks in
  services.bind.enable = lib.mkForce false;

  services.unbound = {
    enable = true;

    settings = {
      server = {
        interface = [ "0.0.0.0" "::0" ];
        port = 53;

        do-ip4 = true;
        do-ip6 = true;
        do-udp = true;
        do-tcp = true;

        access-control =
          [ "127.0.0.0/8 allow" ]
          ++ map (n: "${n} allow") v4Nets;

        # Authoritative local zones
        local-zone =
          [ "${domain} static" ]
          ++ map (z: "${z} static") reverseZonesV4;

        # Actual records (THIS WAS MISSING)
        local-data = localDataA;
        local-data-ptr = localDataPtr;

        auto-trust-anchor-file = "/var/lib/unbound/root.key";

        hide-identity = true;
        hide-version = true;
        harden-glue = true;
        harden-dnssec-stripped = true;
        qname-minimisation = true;

        prefetch = true;
        cache-min-ttl = 60;
        cache-max-ttl = 86400;
      };

      # Recursive for everything outside lan.
      forward-zone = [
        {
          name = ".";
          forward-addr = upstream;
          forward-first = true;
        }
      ];

      remote-control = {
        control-enable = true;
        control-interface = "127.0.0.1";
        control-port = 8953;
      };
    };
  };

  networking.nameservers = [ "127.0.0.1" ];
}

