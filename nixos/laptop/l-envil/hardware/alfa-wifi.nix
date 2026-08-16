{ config, lib, pkgs, relativeRepo, ... }:

# Temporary ALFA USB AP on l-envil, bridging the neon client networks onto the
# cobalt LAN trunk. The Ralink RT3070 (rt2800usb) supports up to 8 AP VAPs, so
# we host two SSIDs here (clients VLAN 30, clients-vpn VLAN 31).
let
  ifname = "wlp0s20f0u2u4u2";
in
{
  sops.secrets = {
    "l-envil-wifi-clients" = {
      sopsFile = relativeRepo.sourcePath "secrets/l-envil-default-wifi.yaml";
      key = "wifi-clients";
    };
    "l-envil-wifi-clients-vpn" = {
      sopsFile = relativeRepo.sourcePath "secrets/l-envil-default-wifi.yaml";
      key = "wifi-clients-vpn";
    };
  };

  # The second BSS needs its own virtual interface (VAP); hostapd does not
  # create it for us.
  systemd.services.alfa-vap = {
    description = "Create the secondary ALFA AP VAP";
    wantedBy = [ "hostapd.service" ];
    before = [ "hostapd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.iw}/bin/iw phy phy1 interface add ${ifname}-1 type __ap 2>/dev/null || true
    '';
  };

  # Per-SSID VLAN sub-interfaces and bridges on the cobalt LAN trunk.
  systemd.network.netdevs = {
    "20-vlan30" = {
      netdevConfig = {
        Name = "vlan30";
        Kind = "vlan";
      };
      vlanConfig.Id = 30;
    };
    "20-vlan31" = {
      netdevConfig = {
        Name = "vlan31";
        Kind = "vlan";
      };
      vlanConfig.Id = 31;
    };
    "20-br-wifi-clients" = {
      netdevConfig = {
        Name = "br-wifi-clients";
        Kind = "bridge";
      };
    };
    "20-br-wifi-clients-vpn" = {
      netdevConfig = {
        Name = "br-wifi-clients-vpn";
        Kind = "bridge";
      };
    };
  };

  systemd.network.networks = {
    "20-vlan30" = {
      matchConfig.Name = "vlan30";
      networkConfig.Bridge = "br-wifi-clients";
    };
    "20-vlan31" = {
      matchConfig.Name = "vlan31";
      networkConfig.Bridge = "br-wifi-clients-vpn";
    };
    "20-br-wifi-clients" = {
      matchConfig.Name = "br-wifi-clients";
      networkConfig = { };
    };
    "20-br-wifi-clients-vpn" = {
      matchConfig.Name = "br-wifi-clients-vpn";
      networkConfig = { };
    };
    "20-br-cobalt-lan-vlans" = {
      matchConfig.Name = "br-cobalt-lan";
      networkConfig.VLAN = [ "vlan30" "vlan31" ];
    };
  };

  services.hostapd = {
    enable = true;
    radios.${ifname} = {
      band = "2g";
      channel = 6;
      countryCode = "NL";
      networks = {
        "${ifname}" = {
          ssid = "neon-clients";
          bssid = "96:fa:21:a0:d7:1b";
          authentication = {
            mode = "wpa3-sae";
            saePasswords = [{ passwordFile = config.sops.secrets."l-envil-wifi-clients".path; }];
          };
          settings = { bridge = "br-wifi-clients"; };
        };
        "${ifname}-1" = {
          ssid = "neon-clients-vpn";
          bssid = "9e:fa:21:a0:d7:1b";
          authentication = {
            mode = "wpa3-sae";
            saePasswords = [{ passwordFile = config.sops.secrets."l-envil-wifi-clients-vpn".path; }];
          };
          settings = { bridge = "br-wifi-clients-vpn"; };
        };
      };
    };
  };
}
