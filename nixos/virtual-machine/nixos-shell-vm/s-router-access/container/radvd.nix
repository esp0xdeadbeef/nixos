{
  config,
  pkgs,
  lib,
  vlanId,
  outPath,
  fabricNodeContext,
  ...
}:

let
  fabricImported = import "${outPath}/library/100-fabric-routing/inputs/intent.nix";
  fabric =
    if builtins.isFunction fabricImported then
      fabricImported { inherit lib; }
    else
      fabricImported;

  inventoryImported = import ../inventory.nix;
  inventory =
    if builtins.isFunction inventoryImported then
      inventoryImported { inherit lib; }
    else
      inventoryImported;

  ulaPrefix = fabric.ulaPrefix or "fd42:dead:beef";

  siteImported = import "${outPath}/library/100-fabric-routing/lib/site-defaults.nix";
  site =
    if builtins.isFunction siteImported then
      siteImported { inherit lib; }
    else
      siteImported;

  domainRaw = site.domain or "lan.";
  domain = if lib.hasSuffix "." domainRaw then domainRaw else "${domainRaw}.";

  lanIf = "lan-${toString vlanId}";

  attachments =
    if fabricNodeContext ? attachments && builtins.isList fabricNodeContext.attachments then
      fabricNodeContext.attachments
    else
      [ ];

  tenantAttachments =
    builtins.filter (
      a:
        builtins.isAttrs a
        && (a.kind or null) == "tenant"
        && (a ? name)
    ) attachments;

  tenantName =
    if builtins.length tenantAttachments == 1 then
      (builtins.head tenantAttachments).name
    else
      null;

  tenantPrefixMap =
    if inventory ? tenantPrefixMap && builtins.isAttrs inventory.tenantPrefixMap then
      inventory.tenantPrefixMap
    else
      { };

  explicitPrefixes =
    if tenantName != null && builtins.hasAttr tenantName tenantPrefixMap then
      tenantPrefixMap.${tenantName}
    else
      [ ];

  prefixes =
    if explicitPrefixes != [ ] then
      explicitPrefixes
    else
      [ "${ulaPrefix}:${toString vlanId}::/64" ];

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
  environment.systemPackages = [
    pkgs.radvd
    pkgs.iproute2
  ];

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
