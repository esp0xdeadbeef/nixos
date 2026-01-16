# file: ./network-clean.nix
{ config, pkgs, lib, ... }:

{
  networking.useNetworkd = true;
  networking.useDHCP = false;
  networking.networkmanager.enable = lib.mkForce false;

  # Disable networkd-wait-online
  systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;

  systemd.network = {
    enable = true;

    # Bridge definitions (vmbr0-vmbr5)
    netdevs = {
      "10-vmbr0" = {
        netdevConfig = {
          Name = "vmbr0";
          Kind = "bridge";
        };
      };
      "10-vmbr1" = {
        netdevConfig = {
          Name = "vmbr1";
          Kind = "bridge";
        };
      };
      "10-vmbr2" = {
        netdevConfig = {
          Name = "vmbr2";
          Kind = "bridge";
        };
      };
      "10-vmbr3" = {
        netdevConfig = {
          Name = "vmbr3";
          Kind = "bridge";
        };
      };
      "10-vmbr4" = {
        netdevConfig = {
          Name = "vmbr4";
          Kind = "bridge";
        };
      };
      "10-vmbr5" = {
        netdevConfig = {
          Name = "vmbr5";
          Kind = "bridge";
        };
      };

      # VLAN interface for management
      "15-ens19-vlan2" = {
        netdevConfig = {
          Name = "ens19.2";
          Kind = "vlan";
        };
        vlanConfig.Id = 2;
      };
    };

    # Network configurations
    networks = {
      # ens19.2 (VLAN 2) -> vmbr0 for management
      "10-ens19.2" = {
        matchConfig.Name = "ens19.2";
        networkConfig = {
          Bridge = "vmbr0";
          DHCP = "no";
          LinkLocalAddressing = "no";
        };
      };

      # ens19 parent interface
      "10-ens19" = {
        matchConfig.Name = "ens19";
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          VLAN = "ens19.2";
        };
      };

      # Other interfaces -> bridges
      "10-ens18" = {
        matchConfig.Name = "ens18";
        networkConfig = {
          Bridge = "vmbr5";
          DHCP = "no";
          LinkLocalAddressing = "no";
        };
      };
      # ISP:
      "10-ens20" = {
        matchConfig.Name = "ens20";
        networkConfig = {
          Bridge = "vmbr3";
          DHCP = "no";
          LinkLocalAddressing = "no";
        };
      };
      # lan (vlan aware)
      "10-ens21" = {
        matchConfig.Name = "ens21";
        networkConfig = {
          Bridge = "vmbr4";
          DHCP = "no";
          LinkLocalAddressing = "no";
        };
      };
      # lan temp-test-trunk
      "10-ens22" = {
        matchConfig.Name = "ens22";
        networkConfig = {
          Bridge = "vmbr1";
          DHCP = "no";
          LinkLocalAddressing = "no";
        };
      };
      # lan - 10gbps to juniper switch
      "10-ens23" = {
        matchConfig.Name = "ens23";
        networkConfig = {
          Bridge = "vmbr2";
          DHCP = "no";
          LinkLocalAddressing = "no";
        };
      };

      # Bridge configurations
      "20-vmbr0" = {
        matchConfig.Name = "vmbr0";
        networkConfig = {
          DHCP = "no";
          ConfigureWithoutCarrier = true;
        };
        address = [
          "192.168.1.71/24"
        ];
        routes = [
          {
            routeConfig = {
              Gateway = "192.168.1.1";
            };
          }
        ];
      };
      "20-vmbr1" = {
        matchConfig.Name = "vmbr1";
        networkConfig = {
          DHCP = "no";
          ConfigureWithoutCarrier = true;
          LinkLocalAddressing = "ipv6";
        };
      };
      "20-vmbr2" = {
        matchConfig.Name = "vmbr2";
        networkConfig = {
          DHCP = "no";
          ConfigureWithoutCarrier = true;
          LinkLocalAddressing = "ipv6";
        };
      };
      "20-vmbr3" = {
        matchConfig.Name = "vmbr3";
        networkConfig = {
          DHCP = "no";
          ConfigureWithoutCarrier = true;
          LinkLocalAddressing = "ipv6";
        };
      };
      "20-vmbr4" = {
        matchConfig.Name = "vmbr4";
        networkConfig = {
          DHCP = "no";
          ConfigureWithoutCarrier = true;
          LinkLocalAddressing = "ipv6";
        };
      };
      "20-vmbr5" = {
        matchConfig.Name = "vmbr5";
        networkConfig = {
          DHCP = "no";
          ConfigureWithoutCarrier = true;
          LinkLocalAddressing = "ipv6";
        };
      };
    };
  };
}

