{
  pkgs,
  lib,
  helpers,
  args,
}:
{ config, ... }:

let
  dhcpLans = lib.filter (l: l.dhcp4 or false) (args.lans or [ ]);

  domain = args.domain or "lan.";

  inherit (helpers) reverseZoneV4_24 ipv4Base3;

  reverseZones = map (l: reverseZoneV4_24 l.ip4) dhcpLans;

  bindPort = 5353;
  d2Port = 53001;

  # Paths in StateDirectory
  bindDir = "/var/lib/bind";
  zoneFileFor =
    z:
    # keep filenames simple: lan. -> db.lan, 1.168.192.in-addr.arpa. -> db.1.168.192.in-addr.arpa
    let
      z2 = lib.removeSuffix "." z;
    in
    "${bindDir}/db.${z2}";

  mkBindZoneStanza = z: ''
    zone "${z}" {
      type master;
      file "${zoneFileFor z}";
      allow-update { 127.0.0.1; ::1; };  // no TSIG, localhost only
      allow-query { 127.0.0.1; ::1; };
    };
  '';

  bindNamedConf = ''
    options {
      directory "${bindDir}";
      pid-file "${bindDir}/named.pid";

      recursion no;

      listen-on port ${toString bindPort} { 127.0.0.1; };
      listen-on-v6 port ${toString bindPort} { ::1; };

      allow-query { 127.0.0.1; ::1; };
    };

    ${mkBindZoneStanza domain}
    ${lib.concatStringsSep "\n" (map mkBindZoneStanza reverseZones)}
  '';

  # Minimal SOA/NS seed; dynamic updates will add A/PTR.
  mkZoneSeed = z: ''
    $TTL 60
    @   IN SOA ns1.${domain} hostmaster.${domain} (
          1   ; serial
          60  ; refresh
          60  ; retry
          3600; expire
          60  ; minimum
        )
        IN NS  ns1.${domain}

    ns1 IN A 127.0.0.1
  '';

  # Kea D2 config (no TSIG; updates BIND on localhost:5353)
  d2Config = builtins.toJSON {
    "DhcpDdns" = {
      "ip-address" = "127.0.0.1";
      "port" = d2Port;

      "forward-ddns" = {
        "ddns-domains" = [
          {
            "name" = domain;
            "dns-servers" = [
              {
                "ip-address" = "127.0.0.1";
                "port" = bindPort;
              }
            ];
          }
        ];
      };

      "reverse-ddns" = {
        "ddns-domains" = map (rz: {
          "name" = rz;
          "dns-servers" = [
            {
              "ip-address" = "127.0.0.1";
              "port" = bindPort;
            }
          ];
        }) reverseZones;
      };
    };
  };

  # Unbound stubs private zones to BIND and does recursion for everything else.
  unboundStubZones = [
    {
      name = domain;
      "stub-addr" = "127.0.0.1@${toString bindPort}";
    }
  ]
  ++ map (rz: {
    name = rz;
    "stub-addr" = "127.0.0.1@${toString bindPort}";
  }) reverseZones;

in
{
  #### Authoritative DNS (BIND) on localhost:5353 ####
  environment.etc."bind/named.conf".text = bindNamedConf;

  systemd.services.bind9 = {
    description = "BIND9 authoritative (local) for ${domain}";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      StateDirectory = "bind";
      StateDirectoryMode = "0755";

      # Create zone seeds if missing
      ExecStartPre = pkgs.writeShellScript "bind-zones-init" ''
                set -euo pipefail
                mkdir -p ${bindDir}

                ensure_zone() {
                  local zone="$1"
                  local file="$2"
                  if [ ! -e "$file" ]; then
                    umask 077
                    cat >"$file" <<'EOF'
        ${mkZoneSeed "${domain}"}
        EOF
                    # The seed contains ns1.${domain}; that's fine for all zones as a bootstrap.
                  fi
                }

                ensure_zone "${domain}" "${zoneFileFor domain}"

                ${lib.concatStringsSep "\n" (
                  map (rz: ''
                    ensure_zone "${rz}" "${zoneFileFor rz}"
                  '') reverseZones
                )}
      '';

      ExecStart = "${pkgs.bind}/sbin/named -g -c /etc/bind/named.conf";
      Restart = "always";
      RestartSec = "2s";
    };
  };

  #### Kea DHCP-DDNS (D2) ####
  environment.etc."kea/dhcp-ddns.json".text = d2Config;

  systemd.services.kea-dhcp-ddns = {
    description = "Kea DHCP-DDNS (D2)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "bind9.service"
      "systemd-networkd.service"
    ];
    requires = [
      "bind9.service"
      "systemd-networkd.service"
    ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.kea}/bin/kea-dhcp-ddns -d -c /etc/kea/dhcp-ddns.json";
      Restart = "always";
      RestartSec = "2s";
    };
  };

  #### Recursive resolver for clients (Unbound) on :53 ####
  services.unbound = {
    enable = true;

    settings = {
      server = {
        interface = [
          "0.0.0.0"
          "::0"
        ];

        access-control = [
          "127.0.0.0/8 allow"
          "::1 allow"
          "10.0.0.0/8 allow"
          "172.16.0.0/12 allow"
          "192.168.0.0/16 allow"
          "fd00::/8 allow"
        ];

        # Optional sanity
        hide-identity = "yes";
        hide-version = "yes";
      };

      # Use Unbound's stub-zone mechanism for private authoritative data
      "stub-zone" = unboundStubZones;

      # Upstream recursion via your provided upstream DNS (optional; remove if you want full recursion)
      # If you want forwarding instead of full recursion, uncomment below:
      # "forward-zone" = [
      #   {
      #     name = ".";
      #     "forward-addr" = (args.upstreamDns or [ ]);
      #   }
      # ];
    };
  };

  #### Make the router itself use Unbound ####
  services.resolved.enable = false;
  networking.useHostResolvConf = lib.mkForce false;
  environment.etc."resolv.conf".text = ''
    nameserver 127.0.0.1
  '';
}
