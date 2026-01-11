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
  vlan2 = "vlan2";
  vlan4 = "vlan4";
  vlan5 = "vlan5";
  vlan6 = "vlan6";
  vlan7 = "vlan7";

  mkVpnConfigService =
    name: tun: secretName:
    pkgs.writeShellScript "write-vpn-config-${name}" ''
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
in
{
  networking.useNetworkd = lib.mkForce true;

  # VLANs for downstream networks
  networking.vlans = {
    vlan2 = {
      interface = "eth1";
      id = 2;
    };
    vlan4 = {
      interface = "eth1";
      id = 4;
    };
    vlan5 = {
      interface = "eth1";
      id = 5;
    };
    vlan6 = {
      interface = "eth1";
      id = 6;
    };
    vlan7 = {
      interface = "eth1";
      id = 7;
    };
  };

  # Bridges (used by containers)
  networking.bridges = {
    br-vlan2.interfaces = [ "vlan2" ];
    br-vlan4.interfaces = [ "vlan4" ];
    br-vlan5.interfaces = [ "vlan5" ];
    br-vlan6.interfaces = [ "vlan6" ];
    br-vlan7.interfaces = [ "vlan7" ];
  };

  # Disable autoconfig on non-primary adapters and bridges
  systemd.network = {
    enable = true;
    networks = {
      "eth1" = {
        matchConfig.Name = "eth1";
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
          ConfigureWithoutCarrier = true;
        };
      };
      "br-vlan2" = {
        matchConfig.Name = "br-vlan2";
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          ConfigureWithoutCarrier = true;
        };
      };
      "br-vlan4" = {
        matchConfig.Name = "br-vlan4";
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          ConfigureWithoutCarrier = true;
        };
      };
      "br-vlan5" = {
        matchConfig.Name = "br-vlan5";
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          ConfigureWithoutCarrier = true;
        };
      };
      "br-vlan6" = {
        matchConfig.Name = "br-vlan6";
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          ConfigureWithoutCarrier = true;
        };
      };
      "br-vlan7" = {
        matchConfig.Name = "br-vlan7";
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          ConfigureWithoutCarrier = true;
        };
      };
    };
  };

  # Disable IPv6 RA on all bridges
  boot.kernel.sysctl = {
    "net.ipv6.conf.all.accept_ra" = 0;
    "net.ipv6.conf.default.accept_ra" = 0;
    "net.ipv6.conf.br-vlan2.accept_ra" = 0;
    "net.ipv6.conf.br-vlan4.accept_ra" = 0;
    "net.ipv6.conf.br-vlan5.accept_ra" = 0;
    "net.ipv6.conf.br-vlan6.accept_ra" = 0;
    "net.ipv6.conf.br-vlan7.accept_ra" = 0;
  };

  # VPN containers configuration
  containers."lan-to-vpn-vlan4" = {
    autoStart = true;
    privateNetwork = true;
    extraVeths = {
      "wan-vlan4".hostBridge = "br-vlan7";
      "lan-vlan4".hostBridge = "br-vlan4";
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
      "wan-vlan5".hostBridge = "br-vlan7";
      "lan-vlan5".hostBridge = "br-vlan5";
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
      "wan-vlan6".hostBridge = "br-vlan7";
      "lan-vlan6".hostBridge = "br-vlan6";
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

  systemd.services."container@lan-to-vpn-vlan4".serviceConfig.ConditionPathExists =
    "/etc/vpn/tun0.conf";
  systemd.services."container@lan-to-vpn-vlan5".serviceConfig.ConditionPathExists =
    "/etc/vpn/tun2.conf";
  systemd.services."container@lan-to-vpn-vlan6".serviceConfig.ConditionPathExists =
    "/etc/vpn/tun3.conf";

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

  systemd.services."write-vpn-config-vlan4" = {
    description = "Decode config";
    wantedBy = [ "network-pre.target" ];
    before = [ "network-online.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkVpnConfigService "vlan4" "tun0" "vpn-lan-to-vpn-vlan4";
    };
  };


  systemd.services."write-vpn-config-vlan5" = {
    description = "Decode config";
    wantedBy = [ "network-pre.target" ];
    before = [ "network-online.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkVpnConfigService "vlan5" "tun2" "vpn-lan-to-vpn-vlan5";
    };
  };

  systemd.services."write-vpn-config-vlan6" = {
    description = "Decode config";
    wantedBy = [ "network-pre.target" ];
    before = [ "network-online.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkVpnConfigService "vlan6" "tun3" "vpn-lan-to-vpn-vlan6";
    };
  };
systemd.tmpfiles.rules = [ "d /etc/vpn 0755 root root -" ];
}
