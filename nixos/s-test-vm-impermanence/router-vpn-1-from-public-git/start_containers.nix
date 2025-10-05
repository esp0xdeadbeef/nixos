{ config, pkgs, lib, inputs, ... }:

let
  inherit (lib) mkMerge mkEnableOption mkOption types nameValuePair mapAttrs mapAttrs';

  nameAirvpn = "airvpn";
  nameMullvad = "mullvad";

  mkVpnConfigService = name: tun: secretName: pkgs.writeShellScript "write-vpn-config-${name}" ''
    set -euxo pipefail
    mkdir -p /etc/vpn/
    secret_path="${config.sops.secrets.${secretName}.path}"
    if [ -f "$secret_path" ] && [ -s "$secret_path" ]; then
      cat "$secret_path" | ${pkgs.coreutils}/bin/base64 -d > /etc/vpn/${tun}.conf
      chmod 600 /etc/vpn/${tun}.conf
    else
      echo "[ERROR] VPN config secret missing or empty: $secret_path" >&2
      exit 1
    fi
  '';
in {
  networking.useNetworkd = lib.mkForce false;

  networking.vlans = {
    lan100 = { interface = "ens21"; id = 100; };
    lan3001 = { interface = "ens21"; id = 3001; };
  };

  networking.bridges = {
    br-ens19.interfaces = [ "ens19" ];
    br-ens20.interfaces = [ "ens20" ];
    br-lan100.interfaces = [ "lan100" ];       # ens21.100
    br-lan3001.interfaces = [ "lan3001" ];     # ens21.3001
  };

  networking.interfaces."lan100".useDHCP = false;
  networking.interfaces."lan3001".useDHCP = false;

  boot.kernel.sysctl = {
    "net.ipv6.conf.br-ens19.accept_ra" = 0;
    "net.ipv6.conf.br-ens20.accept_ra" = 0;
    "net.ipv6.conf.br-lan100.accept_ra" = 0;
    "net.ipv6.conf.br-lan3001.accept_ra" = 0;
  };

  boot.kernel.sysctl = {
    # "net.ipv4.ip_forward" = 1;
    # "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv6.conf.br-ens20.forwarding" = 1;
    "net.ipv4.conf.br-ens20.forwarding" = 1;
  };

  containers."lan-to-vpn-${nameAirvpn}" = {
    autoStart = true;
    privateNetwork = true;
    extraVeths = {
      "wan-${nameAirvpn}".hostBridge = "br-ens19";
      "lan-${nameAirvpn}".hostBridge = "br-ens20";
    };
    bindMounts."/etc/vpn" = {
      hostPath = "/etc/vpn";
      isReadOnly = true;
    };
    config = { pkgs, config, ... }: {
      imports = [ inputs.nixos-router-vpn-gateway.nixosModules.default ];
      services.router-vpn-gateway = {
        enable = true;
        wanInterface = "wan-${nameAirvpn}";
        lanInterface = "lan-${nameAirvpn}";
        vpnInterface = "tun0";
        vpnProfile = "/etc/vpn/tun0.conf";
        subnets.ipv4 = "10.90.0.1/24";
        subnets.ipv6 = "fd90:dead:beef::1/64";
        dhcp4.enable = true;
        ra.enable = true;
      };
    };
  };

  containers."lan-to-vpn-${nameMullvad}" = {
    autoStart = true;
    privateNetwork = true;
    extraVeths = {
      "wan-${nameMullvad}".hostBridge = "br-ens20";
      "lan-${nameMullvad}".hostBridge = "br-lan3001";
    };
    bindMounts."/etc/vpn" = {
      hostPath = "/etc/vpn";
      isReadOnly = true;
    };
    config = { pkgs, config, ... }: {
      imports = [ inputs.nixos-router-vpn-gateway.nixosModules.default ];
      services.router-vpn-gateway = {
        enable = true;
        wanInterface = "wan-${nameMullvad}";
        lanInterface = "lan-${nameMullvad}";
        vpnInterface = "tun1";
        vpnProfile = "/etc/vpn/tun1.conf";
        subnets.ipv4 = "10.10.0.1/24";
        subnets.ipv6 = "fd10:dead:beef::1/64";
        dhcp4.enable = true;
        ra.enable = true;
      };
    };
  };

  systemd.services."container@lan-to-vpn-${nameAirvpn}".serviceConfig.ConditionPathExists =
    "/etc/vpn/tun0.conf";

  systemd.services."container@lan-to-vpn-${nameMullvad}".serviceConfig.ConditionPathExists =
    "/etc/vpn/tun1.conf";

  sops.secrets."vpn-lan-to-vpn-${nameAirvpn}" = {
    owner = "root"; group = "root"; mode = "0400";
  };

  sops.secrets."vpn-lan-to-vpn-${nameMullvad}" = {
    owner = "root"; group = "root"; mode = "0400";
  };

  systemd.services."write-vpn-config-${nameAirvpn}" = {
    description = "Decode AirVPN config from sops and write to /etc/vpn/tun0.conf";
    wantedBy = [ "network-pre.target" ];
    before = [ "network-online.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkVpnConfigService nameAirvpn "tun0" "vpn-lan-to-vpn-${nameAirvpn}";
    };
  };

  systemd.services."write-vpn-config-${nameMullvad}" = {
    description = "Decode Mullvad config from sops and write to /etc/vpn/tun1.conf";
    wantedBy = [ "network-pre.target" ];
    before = [ "network-online.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkVpnConfigService nameMullvad "tun1" "vpn-lan-to-vpn-${nameMullvad}";
    };
  };
}
