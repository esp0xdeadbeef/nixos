# /home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-access/container-router-access/kea.nix
# FILE: container-router-access/kea.nix
{
  config,
  pkgs,
  lib,
  vlanId,
  outPath,
  ...
}:

let
  fabric = import "${outPath}/library/100-fabric-routing/inputs";
  v4Base = fabric.tenantV4Base or "10.10";

  lanIf = "lan-${toString vlanId}";
  lanName = "lan${toString vlanId}";

  subnet = "${v4Base}.${toString vlanId}.0/24";
  router4 = "${v4Base}.${toString vlanId}.1";

  pool = "${v4Base}.${toString vlanId}.100 - ${v4Base}.${toString vlanId}.200";

  domainRaw =
    (import "${outPath}/library/100-fabric-routing/lib/site-defaults.nix").domain or "lan.";
  domain = if lib.hasSuffix "." domainRaw then domainRaw else "${domainRaw}.";

  outFile = "/run/etc/kea/${lanName}.json";

  genKea = pkgs.writeShellScript "gen-kea-${lanName}" ''
    set -euo pipefail
    mkdir -p /run/etc/kea /var/lib/kea

    cat > "${outFile}" <<'EOF'
    {
      "Dhcp4": {
        "interfaces-config": {
          "interfaces": ["${lanIf}"]
        },
        "lease-database": {
          "type": "memfile",
          "persist": true,
          "name": "/var/lib/kea/${lanName}.leases"
        },
        "subnet4": [
          {
            "id": ${toString vlanId},
            "subnet": "${subnet}",
            "pools": [
              { "pool": "${pool}" }
            ],
            "option-data": [
              { "name": "routers", "data": "${router4}" },
              { "name": "domain-name-servers", "data": "${router4}" },
              { "name": "domain-name", "data": "${domain}" }
            ]
          }
        ]
      }
    }
    EOF
  '';
in
{
  environment.systemPackages = [ pkgs.kea pkgs.iproute2 pkgs.gnugrep pkgs.gawk pkgs.coreutils ];

  systemd.services."gen-kea-${lanName}" = {
    wantedBy = [ "multi-user.target" ];
    before = [ "kea-dhcp4-${lanName}.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = genKea;
      RemainAfterExit = true;
    };
  };
}

