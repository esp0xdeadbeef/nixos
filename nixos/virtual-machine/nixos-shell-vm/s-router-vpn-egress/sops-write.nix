{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  inherit (lib) mkMerge;

  nameAirvpn = "airvpn";
  nameMullvad = "mullvad";
  vlan2 = "veth2";
  vlan4 = "veth4";
  vlan5 = "veth5";
  vlan6 = "veth6";
  vlan7 = "veth7";

  mkVpnConfigService =
    name: tun: secretName:
    pkgs.writeShellScript "write-vpn-config-${name}" ''
      set -euxo pipefail
      mkdir -p /etc/vpn/
      secret_path="${config.sops.secrets.${secretName}.path}"
      if [ -f "$secret_path" ] && [ -s "$secret_path" ]; then
        tmp=$(mktemp)
        ${pkgs.coreutils}/bin/base64 -d "$secret_path" > "$tmp"
        install -m 600 "$tmp" "/etc/vpn/${tun}.conf"
        rm "$tmp"
      else
        echo "[ERROR] VPN config secret missing or empty: $secret_path" >&2
        exit 1
      fi
    '';
in
{

  # VPN containers configuration
  containers."lan-to-vpn-vlan4" = {
    autoStart = true;
    privateNetwork = true;
    extraVeths = {
      "wan-vlan4".hostBridge = "vlan7";
      "lan-vlan4".hostBridge = "vlan4";
    };
    bindMounts."/etc/vpn" = {
      hostPath = "/etc/vpn";
      isReadOnly = true;
    };
    config =
      { pkgs, config, ... }:
      {
        imports = [ inputs.nixos-router-vpn-gateway.nixosModules.default ];
        services.router-vpn-gateway = {
          enable = true;
          wanInterface = "wan-vlan4";
          lanInterface = "lan-vlan4";
          vpnInterface = "tun0";
          vpnProfile = "/etc/vpn/tun0.conf";
          subnets.ipv4 = "10.11.0.1/24";
          subnets.ipv6 = "fd10:dead:beef::1/64";
          dhcp4.enable = true;
          ra.enable = true;
        };
      };
  };

  containers."lan-to-vpn-vlan5" = {
    autoStart = true;
    privateNetwork = true;
    extraVeths = {
      "wan-vlan5".hostBridge = "vlan7";
      "lan-vlan5".hostBridge = "vlan5";
    };
    bindMounts."/etc/vpn" = {
      hostPath = "/etc/vpn";
      isReadOnly = true;
    };
    config =
      { pkgs, config, ... }:
      {
        imports = [ inputs.nixos-router-vpn-gateway.nixosModules.default ];
        services.router-vpn-gateway = {
          enable = true;
          wanInterface = "wan-vlan5";
          lanInterface = "lan-vlan5";
          vpnInterface = "tun2";
          vpnProfile = "/etc/vpn/tun2.conf";
          subnets.ipv4 = "10.13.0.1/24";
          subnets.ipv6 = "fd12:dead:beef::1/64";
          dhcp4.enable = true;
          ra.enable = true;
        };
      };
  };

  containers."lan-to-vpn-vlan6" = {
    autoStart = true;
    privateNetwork = true;
    extraVeths = {
      "wan-vlan6".hostBridge = "vlan7";
      "lan-vlan6".hostBridge = "vlan6";
    };
    bindMounts."/etc/vpn" = {
      hostPath = "/etc/vpn";
      isReadOnly = true;
    };
    config =
      { pkgs, config, ... }:
      {
        imports = [ inputs.nixos-router-vpn-gateway.nixosModules.default ];
        services.router-vpn-gateway = {
          enable = true;
          wanInterface = "wan-vlan6";
          lanInterface = "lan-vlan6";
          vpnInterface = "tun3";
          vpnProfile = "/etc/vpn/tun3.conf";
          subnets.ipv4 = "10.14.0.1/24";
          subnets.ipv6 = "fd14:dead:beef::1/64";
          dhcp4.enable = true;
          ra.enable = true;
        };
      };
  };

  # Secrets for VPN configs
  sops.secrets."vpn-lan-to-vpn-vlan4" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  sops.secrets."vpn-lan-to-vpn-vlan5" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  sops.secrets."vpn-lan-to-vpn-vlan6" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  # Ensure /etc/vpn exists early
  systemd.tmpfiles.rules = [ "d /etc/vpn 0755 root root -" ];

  # Write VPN configs (run once at boot, after sops is ready)
  systemd.services."write-vpn-config-vlan4" = {
    enable = true;
    description = "Decode config";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" "sops-nix.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkVpnConfigService "vlan4" "tun0" "vpn-lan-to-vpn-vlan4";
    };
  };

  systemd.services."write-vpn-config-vlan5" = {
    enable = true;
    description = "Decode config";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" "sops-nix.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkVpnConfigService "vlan5" "tun2" "vpn-lan-to-vpn-vlan5";
    };
  };

  systemd.services."write-vpn-config-vlan6" = {
    enable = true;
    description = "Decode config";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" "sops-nix.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkVpnConfigService "vlan6" "tun3" "vpn-lan-to-vpn-vlan6";
    };
  };

  # Make containers wait for their config file to be written
  systemd.services."container@lan-to-vpn-vlan4" = {
    requires = [ "write-vpn-config-vlan4.service" ];
    after = [ "write-vpn-config-vlan4.service" ];
  };

  systemd.services."container@lan-to-vpn-vlan5" = {
    requires = [ "write-vpn-config-vlan5.service" ];
    after = [ "write-vpn-config-vlan5.service" ];
  };

  systemd.services."container@lan-to-vpn-vlan6" = {
    requires = [ "write-vpn-config-vlan6.service" ];
    after = [ "write-vpn-config-vlan6.service" ];
  };
}

