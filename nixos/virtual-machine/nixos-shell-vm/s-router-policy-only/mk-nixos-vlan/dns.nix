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
  wans = args.wans or [ ];

  #
  # Normalize domain
  #
  domainRaw = args.domain or "lan.";
  domain = if lib.hasSuffix "." domainRaw then domainRaw else "${domainRaw}.";

  #
  # IPv4 client networks
  #
  v4Nets = map (
    l:
    let
      base = helpers.ipv4Base3 l.ip4;
    in
    "${base}.0/24"
  ) (lib.filter (l: l ? ip4) lans);

  #
  # Router bind addresses
  #
  lanV4Addrs = map (l: helpers.stripCidr l.ip4) (lib.filter (l: l ? ip4) lans);
  lanV6Addrs = map (l: helpers.stripCidr l.ip6) (lib.filter (l: l ? ip6) lans);

  #
  # Reverse zones
  #
  reverseZonesV4 = map (l: helpers.reverseZoneV4_24 l.ip4) (lib.filter (l: l ? ip4) lans);

  #
  # Upstream resolvers
  #
  upstream = args.upstreamDns or [ ];

  #
  # Runtime LAN hosts
  #
  runtimeLans = lib.filter (l: l ? runtimeHostsFile) lans;

  #
  # Generate runtime local-data
  #
  genRuntime = pkgs.writeShellScript "gen-unbound-runtime" ''
    set -euo pipefail
    OUT="/run/unbound-local.conf"
    DOMAIN="${domain}"
    mkdir -p /run
    : > "$OUT"

    for IN in ${lib.concatStringsSep " " (map (l: l.runtimeHostsFile) runtimeLans)}; do
      [ -r "$IN" ] || continue

      ${pkgs.jq}/bin/jq -r \
        '.[] | select(.hostname and .["ip-address"]) |
         "local-data: \"\(.hostname).'"$DOMAIN"' A \(.["ip-address"])\""' \
        "$IN" >> "$OUT"

      ${pkgs.jq}/bin/jq -r \
        '.[] | select(.hostname and .["ip-address"]) |
         "local-data-ptr: \"\(.["ip-address"]) \(.hostname).'"$DOMAIN"'\""' \
        "$IN" >> "$OUT"
    done
  '';

  #
  # Generate IPv6 ACLs from WAN PDs
  #
  genWanIpv6Acl = pkgs.writeShellScript "gen-unbound-wan-ipv6-acl" ''
    set -euo pipefail
    OUT="/run/unbound-ipv6-acl.conf"
    mkdir -p /run
    : > "$OUT"

    ${lib.concatStringsSep "\n" (
      map (w: ''
        if [ -r "${w.publicPrefixFile or ""}" ]; then
          PREFIX="$(tr -d ' \t\n\r' < "${w.publicPrefixFile}")"
          echo "access-control: $PREFIX allow" >> "$OUT"
          echo "[dns] allowing WAN ${w.name} prefix $PREFIX"
        fi
      '') (lib.filter (w: w ? publicPrefixFile) wans)
    )}
  '';

in
{
  services.bind.enable = lib.mkForce false;

  services.unbound = {
    enable = true;

    settings.server = {
      interface =
        lanV4Addrs
        ++ lanV6Addrs
        ++ [
          "127.0.0.1"
          "::1"
        ];

      outgoing-interface = lanV4Addrs ++ lanV6Addrs;

      port = 53;
      do-ip4 = true;
      do-ip6 = true;
      do-udp = true;
      do-tcp = true;

      access-control = [
        "127.0.0.0/8 allow"
        "::1 allow"
      ]
      ++ map (n: "${n} allow") v4Nets;

      local-zone = [ "${domain} static" ] ++ map (z: "${z} static") reverseZonesV4;

      include = [
        "/run/unbound-local.conf"
        "/run/unbound-ipv6-acl.conf"
      ];

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

    settings.forward-zone = [
      {
        name = ".";
        forward-addr = upstream;
        forward-first = true;
      }
    ];
  };

  networking.nameservers = [
    "127.0.0.1"
    "::1"
  ];

  systemd.services.gen-unbound-runtime = {
    wantedBy = [ "multi-user.target" ];
    before = [ "unbound.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = genRuntime;
      RemainAfterExit = true;
    };
  };

  systemd.services.gen-unbound-wan-ipv6-acl = {
    wantedBy = [ "multi-user.target" ];
    before = [ "unbound.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = genWanIpv6Acl;
      RemainAfterExit = true;
    };
  };

  systemd.services.unbound = {
    after = [
      "gen-unbound-runtime.service"
      "gen-unbound-wan-ipv6-acl.service"
    ];
    requires = [
      "gen-unbound-runtime.service"
      "gen-unbound-wan-ipv6-acl.service"
    ];
  };
}
