{
  config,
  pkgs,
  lib,
  args,
  ...
}:

let
  helpers = import ./helpers.nix { inherit lib; };
  inherit (helpers) ipv4Base3 defaultPool4 onlyIPv4;

  # LANs with DHCPv4 enabled
  lans = lib.filter (l: l.dhcp4 or false) (args.lans or [ ]);

  upstreamV4 = onlyIPv4 (args.upstreamDns or [ ]);
  domain = args.domain or "lan.";

  #
  # Generator WITH runtime reservations
  #
  genRuntimeService =
    l:
    let
      inFile = l.runtimeHostsFile;
      outFile = "/run/etc/kea/${l.name}.json";

      subnet = "${ipv4Base3 l.ip4}.0/24";
      router = ipv4Base3 l.ip4 + ".1";
      dns = lib.concatStringsSep "," ([ router ] ++ upstreamV4);
    in
    {
      name = "gen-kea-${l.name}";
      value = {
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "gen-kea-${l.name}" ''
            set -euo pipefail
            mkdir -p /run/etc/kea

            if [ ! -r "${inFile}" ]; then
              echo "[kea] WARNING: ${inFile} missing, generating empty reservations"
              echo '[]' > "${inFile}"
            fi

            ${pkgs.jq}/bin/jq \
              --arg subnet "${subnet}" \
              --arg router "${router}" \
              --arg dns "${dns}" \
              --arg domain "${domain}" '
              {
                Dhcp4: {
                  "interfaces-config": {
                    interfaces: ["${l.iface}"]
                  },
                  "lease-database": {
                    type: "memfile",
                    persist: true,
                    name: "/var/lib/kea/${l.name}.leases"
                  },
                  subnet4: [{
                    id: ${toString l.id},
                    subnet: $subnet,
                    pools: [
                      { pool: "${defaultPool4 l.ip4}" }
                    ],
                    "option-data": [
                      { name: "routers", data: $router },
                      { name: "domain-name-servers", data: $dns },
                      { name: "domain-name", data: $domain }
                    ],
                    reservations:
                      ( sort_by(."hw-address")
                      | group_by(."hw-address")
                      | map(.[0])
                      | sort_by(."ip-address")
                      | group_by(."ip-address")
                      | map(.[0])
                      )
                  }]
                }
              }
              ' "${inFile}" > "${outFile}"
          '';
          RemainAfterExit = true;
        };
      };
    };

  #
  # Generator WITHOUT runtime reservations
  #
  genStubService =
    l:
    let
      outFile = "/run/etc/kea/${l.name}.json";

      subnet = "${ipv4Base3 l.ip4}.0/24";
      router = ipv4Base3 l.ip4 + ".1";
      dns = lib.concatStringsSep "," ([ router ] ++ upstreamV4);
    in
    {
      name = "gen-kea-${l.name}";
      value = {
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "gen-kea-${l.name}" ''
                        set -euo pipefail
                        mkdir -p /run/etc/kea

                        cat > "${outFile}" <<EOF
            {
              "Dhcp4": {
                "interfaces-config": {
                  "interfaces": ["${l.iface}"]
                },
                "lease-database": {
                  "type": "memfile",
                  "persist": true,
                  "name": "/var/lib/kea/${l.name}.leases"
                },
                "subnet4": [
                  {
                    "id": ${toString l.id},
                    "subnet": "${subnet}",
                    "pools": [
                      { "pool": "${defaultPool4 l.ip4}" }
                    ],
                    "option-data": [
                      { "name": "routers", "data": "${router}" },
                      { "name": "domain-name-servers", "data": "${dns}" },
                      { "name": "domain-name", "data": "${domain}" }
                    ]
                  }
                ]
              }
            }
            EOF
          '';
          RemainAfterExit = true;
        };
      };
    };

in
{
  systemd.services =
    lib.listToAttrs (map genRuntimeService (lib.filter (l: l ? runtimeHostsFile) lans))
    // lib.listToAttrs (map genStubService (lib.filter (l: !(l ? runtimeHostsFile)) lans));
}
