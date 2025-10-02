{
  config,
  pkgs,
  lib,
  ...
}:

let
  management_interface = "ens18";
  upstream_VPN_interface = "ens19";
  vpnNATInterface = "ens20";

  vpnInterface = "tun0";
  vpnConfBasePath = "/etc/vpn";
  vpnConfPath = "${vpnConfBasePath}/${vpnInterface}.conf";
  vpnIPv4WithMask = "10.90.0.1/24";
  vpnIPv6WithMask = "fd90:dead:beef::100/64";

  # ignore this
  vrf_table_vpn = 10;
  vrf_name_vpn = "vrf-vpn";

in
{

  boot.kernel.sysctl = {
    "net.ipv6.conf.br-wan.accept_ra" = 0;
    "net.ipv6.conf.br-lan.accept_ra" = 0;
  };

  networking.bridges.br-wan.interfaces = [ "ens19" ];
  networking.bridges.br-lan.interfaces = [ "ens20" ];

  systemd.network.networks."br-lan" = {
    matchConfig.Name = "br-lan";
    linkConfig.RequiredForOnline = "no";
    networkConfig.DHCP = "no";
    networkConfig.IPv6AcceptRA = false;
  };

  systemd.network.networks."br-wan" = {
    matchConfig.Name = "br-wan";
    linkConfig.RequiredForOnline = "no";
    networkConfig.DHCP = "no";
    networkConfig.IPv6AcceptRA = false;
  };

  # networking.vlans."ens19.3" = { id = 3; interface = "ens19"; };
  # networking.bridges.br-wan.interfaces = [ "ens19.3" ];

  systemd.services."container@lan-to-vpn-1".serviceConfig.ConditionPathExists = "/etc/vpn/tun0.conf";

  containers.lan-to-vpn-1 = {
    autoStart = true;
    privateNetwork = true;

    extraVeths = {
      wan.hostBridge = "br-wan";
      lan.hostBridge = "br-lan";
    };

    bindMounts."/etc/vpn" = {
      hostPath = "/etc/vpn";
      isReadOnly = true;
    };

    config = import ./build_container-lan-to-tun.nix;
  };

  sops.secrets."vpn-configuration" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  systemd.services.write-vpn-config = {
    description = "Decode VPN config from sops and write to ${vpnConfPath}";
    wantedBy = [ "network-pre.target" ];
    before = [ "network-online.target" ];
    after = [ "local-fs.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "write-vpn-config" ''
        set -euxo pipefail
        mkdir -p ${vpnConfBasePath}
        secret_path="${config.sops.secrets."vpn-configuration".path}"
        if [ -f "$secret_path" ] && [ -s "$secret_path" ]; then
        cat "$secret_path" | ${pkgs.coreutils}/bin/base64 -d > ${vpnConfPath}
        chmod 600 ${vpnConfPath}
        else
        echo "[ERROR] VPN config secret missing or empty: $secret_path" >&2
        exit 1
        fi
      '';
    };
  };
}
