{
  config,
  pkgs,
  lib,
  args,
  ...
}:

let
  helpers = import ./helpers.nix { inherit lib; };

  lans = args.lans or [ ];

  # Normalize domain to FQDN with trailing dot
  domainRaw = args.domain or "lan.";
  domain = if lib.hasSuffix "." domainRaw then domainRaw else "${domainRaw}.";

  # IPv4 forward ACLs (assume /24)
  v4Nets = map (
    l:
    let
      base = helpers.ipv4Base3 l.ip4;
    in
    "${base}.0/24"
  ) lans;

  # Reverse zones derived from LAN IPv4 (/24 only)
  reverseZonesV4 = map (l: helpers.reverseZoneV4_24 l.ip4) lans;

  # Upstream recursive resolvers
  upstream = args.upstreamDns or [ ];

  # LANs that provide runtime host data
  runtimeLans = lib.filter (l: l ? runtimeHostsFile) lans;

  genScript = pkgs.writeShellScript "gen-unbound-runtime" ''
    set -euo pipefail

    OUT="/run/unbound-local.conf"
    DOMAIN="${domain}"

    echo "[dns] generating $OUT"

    mkdir -p /run
    : > "$OUT"

    for IN in ${lib.concatStringsSep " " (map (l: l.runtimeHostsFile) runtimeLans)}; do
      if [ ! -r "$IN" ]; then
        echo "[dns] skipping missing $IN"
        continue
      fi

      ${pkgs.jq}/bin/jq -r \
        '.[] | select(.hostname != null and .["ip-address"] != null) |
         "local-data: \"\(.hostname).'"$DOMAIN"' A \(.["ip-address"])\""' \
        "$IN" >> "$OUT"

      ${pkgs.jq}/bin/jq -r \
        '.[] | select(.hostname != null and .["ip-address"] != null) |
         "local-data-ptr: \"\(.["ip-address"]) \(.hostname).'"$DOMAIN"'\""' \
        "$IN" >> "$OUT"
    done

    if ! ${pkgs.gnugrep}/bin/grep -q . "$OUT"; then
      echo "[dns] WARNING: generated empty $OUT"
    fi
  '';
in
{
  # Hard kill BIND if it ever sneaks in
  services.bind.enable = lib.mkForce false;

  services.unbound = {
    enable = true;

    settings = {
      server = {
        interface = [
          "0.0.0.0"
          "::0"
        ];
        port = 53;

        do-ip4 = true;
        do-ip6 = true;
        do-udp = true;
        do-tcp = true;

        access-control = [ "127.0.0.0/8 allow" ] ++ map (n: "${n} allow") v4Nets;

        local-zone = [ "${domain} static" ] ++ map (z: "${z} static") reverseZonesV4;

        include = [ "/run/unbound-local.conf" ];

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

  systemd.services.gen-unbound-runtime = {
    wantedBy = [ "multi-user.target" ];
    before = [ "unbound.service" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = genScript;
      RemainAfterExit = true;
    };
  };

  systemd.services.unbound = {
    after = [ "gen-unbound-runtime.service" ];
    requires = [ "gen-unbound-runtime.service" ];
  };
}
