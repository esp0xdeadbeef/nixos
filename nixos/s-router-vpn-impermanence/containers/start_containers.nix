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
  vlan5 = "vlan5";
  vlan6 = "vlan6";

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

  # Default WAN (host keeps full routing only here)
  networking.interfaces.ens19.useDHCP = true;

  # VLANs for downstream networks
  networking.vlans = {
    lan5 = {
      interface = "ens21";
      id = 5;
    };
    lan6 = {
      interface = "ens21";
      id = 6;
    };
    lan100 = {
      interface = "ens21";
      id = 100;
    };
    lan3001 = {
      interface = "ens21";
      id = 3001;
    };
  };

  # Bridges (used by containers)
  networking.bridges = {
    br-lan5.interfaces = [ "lan5" ];
    br-lan6.interfaces = [ "lan6" ];
    br-ens19.interfaces = [ "ens19" ];
    br-ens20.interfaces = [ "ens20" ];
    br-lan100.interfaces = [ "lan100" ];
    br-lan3001.interfaces = [ "lan3001" ];
  };

  # Disable autoconfig on non-primary adapters and bridges
  systemd.network = {
    enable = true;
    networks = {
      "ens20" = {
        matchConfig.Name = "ens20";
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
          ConfigureWithoutCarrier = true;
        };
      };
      "ens21" = {
        matchConfig.Name = "ens21";
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
          ConfigureWithoutCarrier = true;
        };
      };
      "br-ens19" = {
        matchConfig.Name = "br-ens19";
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          ConfigureWithoutCarrier = true;
        };
      };
      "br-ens20" = {
        matchConfig.Name = "br-ens20";
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          ConfigureWithoutCarrier = true;
        };
      };
      "br-lan5" = {
        matchConfig.Name = "br-lan100";
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          ConfigureWithoutCarrier = true;
        };
      };
      "br-lan6" = {
        matchConfig.Name = "br-lan3001";
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          ConfigureWithoutCarrier = true;
        };
      };
      "br-lan100" = {
        matchConfig.Name = "br-lan100";
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          ConfigureWithoutCarrier = true;
        };
      };
      "br-lan3001" = {
        matchConfig.Name = "br-lan3001";
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
    "net.ipv6.conf.br-ens19.accept_ra" = 0;
    "net.ipv6.conf.br-ens20.accept_ra" = 0;
    "net.ipv6.conf.br-lan5.accept_ra" = 0;
    "net.ipv6.conf.br-lan6.accept_ra" = 0;
    "net.ipv6.conf.br-lan100.accept_ra" = 0;
    "net.ipv6.conf.br-lan3001.accept_ra" = 0;
  };

  # VPN containers configuration
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
    config =
      { pkgs, config, ... }:
      {
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
    config =
      { pkgs, config, ... }:
      {
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
        

      #   # Disable systemd-resolved integration and use NM to manage resolv.conf
      #   networking.networkmanager = {
      #     enable = true;
      #     dns = "default";
      #   };

      #   # Remove any existing resolv.conf symlinks or stub files at boot
      #   systemd.tmpfiles.rules = [
      #     "L+ /etc/resolv.conf - - - - /run/NetworkManager/resolv.conf"
      #   ];

      #   # Optional: mask resolvconf service if it exists in base container image
      #   systemd.services.resolvconf.enable = false;
      #   environment.systemPackages = with pkgs; [
      #     dnsutils
      #     openvpn
      #     wireguard-tools
      #     tcpdump
      #     traceroute
      #     nftables
      #     dhcpcd
      #     tmux
      #     tshark
      #   ];
      };
  };

  systemd.services."container@lan-to-vpn-${nameAirvpn}".serviceConfig.ConditionPathExists =
    "/etc/vpn/tun0.conf";
  systemd.services."container@lan-to-vpn-${nameMullvad}".serviceConfig.ConditionPathExists =
    "/etc/vpn/tun1.conf";

  systemd.services."container@lan-to-vpn-${vlan5}".serviceConfig.ConditionPathExists =
    "/etc/vpn/tun2.conf";
  systemd.services."container@lan-to-vpn-${vlan6}".serviceConfig.ConditionPathExists =
    "/etc/vpn/tun3.conf";

  # Decode VPN profiles from sops secrets
  sops.secrets."vpn-lan-to-vpn-${nameAirvpn}" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };
  sops.secrets."vpn-lan-to-vpn-${nameMullvad}" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  # Decode VPN profiles from sops secrets
  sops.secrets."vpn-lan-to-vpn-${vlan5}" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  sops.secrets."vpn-lan-to-vpn-${vlan6}" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  systemd.services."write-vpn-config-${vlan5}" = {
    description = "Decode AirVPN config";
    wantedBy = [ "network-pre.target" ];
    before = [ "network-online.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkVpnConfigService vlan5 "tun0" "vpn-lan-to-vpn-${vlan5}";
    };
  };

  systemd.services."write-vpn-config-${vlan6}" = {
    description = "Decode Mullvad config";
    wantedBy = [ "network-pre.target" ];
    before = [ "network-online.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkVpnConfigService vlan6 "tun1" "vpn-lan-to-vpn-${vlan6}";
    };
  };

  systemd.services."write-vpn-config-${nameAirvpn}" = {
    description = "Decode AirVPN config";
    wantedBy = [ "network-pre.target" ];
    before = [ "network-online.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkVpnConfigService nameAirvpn "tun0" "vpn-lan-to-vpn-${nameAirvpn}";
    };
  };

  systemd.services."write-vpn-config-${nameMullvad}" = {
    description = "Decode Mullvad config";
    wantedBy = [ "network-pre.target" ];
    before = [ "network-online.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkVpnConfigService nameMullvad "tun1" "vpn-lan-to-vpn-${nameMullvad}";
    };
  };
}
