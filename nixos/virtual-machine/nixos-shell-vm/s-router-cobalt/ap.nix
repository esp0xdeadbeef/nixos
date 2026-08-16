{ config, lib, pkgs, ... }:

# Temporary ALFA USB AP container inside the cobalt router VM. The USB
# device is passed through via qemu-xhci and the wlan0 interface is moved
# into this container with --network-interface. Each SSID bridges onto a
# veth trunk (ve-ap) which is wired to the LAN trunk, so the SSIDs land on
# the same VLANs as the wired access containers.
let
  wifiIf = "wlan0";
in
{
  containers.ap = {
    autoStart = true;
    privateNetwork = true;
    interfaces = [ wifiIf ];
    extraVeths."ve-ap" = { hostBridge = "br-lan-trunk"; };

    bindMounts = {
      "/run/secrets/wifi-clients" = {
        hostPath = config.sops.secrets."cobalt-wifi-clients".path;
        isReadOnly = true;
      };
      "/run/secrets/wifi-clients-vpn" = {
        hostPath = config.sops.secrets."cobalt-wifi-clients-vpn".path;
        isReadOnly = true;
      };
    };

    config = { config, lib, pkgs, ... }: {
      # The rt2800usb cannot set its MAC from inside a non-initial netns, and
      # the hostapd module demands an explicit bssid for multi-BSS. Drop both:
      # the adapter's existing (non-real) MACs are used as the BSSIDs.
      assertions = lib.filter (a: !lib.hasInfix "bssid must be specified" a.message) config.assertions;

      systemd.services.ap-vap = {
        description = "Create the secondary ALFA AP VAP";
        wantedBy = [ "hostapd.service" ];
        before = [ "hostapd.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${pkgs.iw}/bin/iw phy phy0 interface add ${wifiIf}-1 type __ap 2>/dev/null || true
        '';
      };

      # The wireless interface is moved into this container via
      # --network-interface, so systemd cannot track it as a device unit.
      # Drop hostapd's device binding and let ap-vap order the start.
      systemd.services.hostapd.bindsTo = lib.mkForce [ ];
      systemd.services.hostapd.after = lib.mkForce [ "ap-vap.service" ];

      systemd.network.netdevs = {
        "20-ap-vlan30" = {
          netdevConfig = { Name = "ve-ap.30"; Kind = "vlan"; };
          vlanConfig.Id = 30;
        };
        "20-ap-vlan31" = {
          netdevConfig = { Name = "ve-ap.31"; Kind = "vlan"; };
          vlanConfig.Id = 31;
        };
        "20-br-wifi-clients" = {
          netdevConfig = { Name = "br-wifi-clients"; Kind = "bridge"; };
        };
        "20-br-wifi-clients-vpn" = {
          netdevConfig = { Name = "br-wifi-clients-vpn"; Kind = "bridge"; };
        };
      };

      systemd.network.networks = {
        "20-ve-ap" = {
          matchConfig.Name = "ve-ap";
          networkConfig.VLAN = [ "ve-ap.30" "ve-ap.31" ];
        };
        "20-ap-vlan30" = {
          matchConfig.Name = "ve-ap.30";
          networkConfig.Bridge = "br-wifi-clients";
        };
        "20-ap-vlan31" = {
          matchConfig.Name = "ve-ap.31";
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
      };

      services.hostapd = {
        enable = true;
        radios.${wifiIf} = {
          band = "2g";
          channel = 6;
          countryCode = "NL";
          networks = {
            "${wifiIf}" = {
              ssid = "neon-clients";
              authentication = {
                mode = "wpa3-sae";
                saePasswords = [{ passwordFile = "/run/secrets/wifi-clients"; }];
              };
              settings = { bridge = "br-wifi-clients"; };
            };
            "${wifiIf}-1" = {
              ssid = "neon-clients-vpn";
              authentication = {
                mode = "wpa3-sae";
                saePasswords = [{ passwordFile = "/run/secrets/wifi-clients-vpn"; }];
              };
              settings = { bridge = "br-wifi-clients-vpn"; };
            };
          };
        };
      };
    };
  };
}
