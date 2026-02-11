# /home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-access/container-router-access/radvd.nix
# FILE: container-router-access/radvd.nix
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
  ulaPrefix = fabric.ulaPrefix or "fd42:dead:beef";

  site = import "${outPath}/library/100-fabric-routing/lib/site-defaults.nix";
  domainRaw = site.domain or "lan.";
  domain = if lib.hasSuffix "." domainRaw then domainRaw else "${domainRaw}.";

  nodeName = "s-router-access-${toString vlanId}";
  lanIf = "lan-${toString vlanId}";

  # Pull synthesized prefixes from the library (ULA + optional GUA)
  routed = import "${outPath}/library/100-fabric-routing/generated/30-routing.nix" { inherit lib; };

  # Find the tenant LAN link and endpoint for this node
  lanLinkName = "access-tenant-${toString vlanId}";
  ep =
    (((routed.links or { }).${lanLinkName} or { }).endpoints or { }).${nodeName} or { };

  prefixes =
    let
      xs = ep.ra6Prefixes or [ ];
    in
    if xs == [ ] then
      # fallback: always advertise ULA /64
      [ "${ulaPrefix}:${toString vlanId}::/64" ]
    else
      xs;

  rdnss = "${ulaPrefix}:${toString vlanId}::1";
  radvdConf = "/run/radvd.conf";

  gen = pkgs.writeShellScript "gen-radvd-${toString vlanId}" ''
    set -euo pipefail
    mkdir -p /run

    IFACE="${lanIf}"
    : > "${radvdConf}"

    if [ ! -d "/sys/class/net/$IFACE" ]; then
      echo "[radvd] $IFACE missing; not generating RA config" >&2
      exit 0
    fi

    ${pkgs.iproute2}/bin/ip link set "$IFACE" up || true

    cat >> "${radvdConf}" <<EOF
    interface $IFACE {
      AdvSendAdvert on;
      MinRtrAdvInterval 10;
      MaxRtrAdvInterval 30;

      AdvManagedFlag off;
      AdvOtherConfigFlag off;

      RDNSS ${rdnss} {
        AdvRDNSSLifetime 600;
      };

      DNSSL ${domain} {
        AdvDNSSLLifetime 600;
      };
    EOF

    ${lib.concatMapStrings (p: ''
      cat >> "${radvdConf}" <<EOF
      prefix ${p} {
        AdvOnLink on;
        AdvAutonomous on;
      };
      EOF
    '') prefixes}

    echo "};" >> "${radvdConf}"
  '';
in
{
  environment.systemPackages = [ pkgs.radvd pkgs.iproute2 ];

  systemd.services."radvd-generate-${toString vlanId}" = {
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-networkd.service" ];
    requires = [ "systemd-networkd.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = gen;
      RemainAfterExit = true;
    };
  };

  systemd.services."radvd-${toString vlanId}" = {
    wantedBy = [ "multi-user.target" ];
    after = [ "radvd-generate-${toString vlanId}.service" ];
    requires = [ "radvd-generate-${toString vlanId}.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.radvd}/bin/radvd -n -C ${radvdConf}";
      Restart = "always";
      RestartSec = "2s";
    };
  };
}

