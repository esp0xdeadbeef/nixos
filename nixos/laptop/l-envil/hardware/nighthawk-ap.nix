{ config, lib, pkgs, inputs, relativeRepo, ... }:

# Nighthawk AXE3000 (mt7925u, 0846:9072) AP on the cobalt site host. It owns
# the 5 GHz clients and clients-vpn SSIDs and bridges them into the cobalt
# router's LAN trunk via VLAN sub-interfaces so the traffic lands on the
# clients (VLAN 30) and clients-vpn (VLAN 31) access networks inside the VM.
let
  ssidList = inputs.wifi-ssids.outPath + "/ssids.txt";
  deriveSsid = pkgs.writeShellScript "derive-ssid-nh" (
    builtins.readFile (relativeRepo.sourcePath "library/01-general/network/wifi-ssid-derive.sh")
  );

  ctrl = "/run/nh-ap";

  nhClients = "nh-c0";
  nhClientsVpn = "nh-c1";

  vlanClients = "nh-vl30";
  vlanClientsVpn = "nh-vl31";
  brClients = "nh-br30";
  brClientsVpn = "nh-br31";

  hostapdConf = pkgs.writeShellScript "nh-ap-conf" ''
    set -euo pipefail
    SEC=/run/secrets/cobalt-wifi
    YQ=${pkgs.yq-go}/bin/yq
    seed=$("$YQ" -r '.seed' "$SEC")
    used=/run/nh-ap-used
    rm -f "$used"
    ssid1=$(${deriveSsid} "$seed" cobalt-clients ${ssidList} "$used")
    ssid2=$(${deriveSsid} "$seed" cobalt-clients-vpn ${ssidList} "$used")
    pass1=$("$YQ" -r '.cobalt-clients.psk' "$SEC")
    pass2=$("$YQ" -r '.cobalt-clients-vpn.psk' "$SEC")
    mkdir -p ${ctrl}

    cat > ${ctrl}/${nhClients}.conf <<EOF
    ctrl_interface=${ctrl}
    interface=${nhClients}
    driver=nl80211
    ssid=$ssid1
    hw_mode=a
    channel=36
    wmm_enabled=1
    country_code=NL
    wpa=2
    wpa_key_mgmt=WPA-PSK
    wpa_pairwise=CCMP
    wpa_passphrase=$pass1
    bridge=${brClients}
    EOF

    cat > ${ctrl}/${nhClientsVpn}.conf <<EOF
    ctrl_interface=${ctrl}
    interface=${nhClientsVpn}
    driver=nl80211
    ssid=$ssid2
    hw_mode=a
    channel=36
    wmm_enabled=1
    country_code=NL
    wpa=2
    wpa_key_mgmt=WPA-PSK
    wpa_pairwise=CCMP
    wpa_passphrase=$pass2
    bridge=${brClientsVpn}
    EOF
  '';

  nhPhy = "phy1";

  mkApUnit =
    vap: bridge: gw: {
      name = "nh-ap-${vap}";
      value = {
        description = "Nighthawk 5GHz AP ${vap} on bridge ${bridge}";
        wantedBy = [ "multi-user.target" ];
        after = [ "nh-ap-conf.service" "nh-vap.service" ];
        requires = [ "nh-ap-conf.service" "nh-vap.service" ];
        path = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.iproute2
        ];
        serviceConfig = {
          ExecStart = "${pkgs.hostapd}/bin/hostapd ${ctrl}/${vap}.conf";
          Restart = "always";
          RestartSec = 3;
        };
        preStart = ''
          for _ in $(seq 1 30); do
            ${pkgs.iproute2}/bin/ip link show ${bridge} 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "state UP" && break
            sleep 1
          done
          ${pkgs.iproute2}/bin/ip link show ${bridge} 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "state UP" || exit 1
        '';
      };
    };
in
{
  sops.secrets."cobalt-wifi" = {
    sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-wifi.yaml";
    key = "";
    path = "/run/secrets/cobalt-wifi";
  };

  systemd.network.netdevs = {
    "20-br-cobalt-lan-30" = {
      netdevConfig = {
        Name = vlanClients;
        Kind = "vlan";
      };
      vlanConfig = {
        Id = 30;
      };
    };
    "20-br-cobalt-lan-31" = {
      netdevConfig = {
        Name = vlanClientsVpn;
        Kind = "vlan";
      };
      vlanConfig = {
        Id = 31;
      };
    };
    "30-br-nh-clients" = {
      netdevConfig = {
        Name = brClients;
        Kind = "bridge";
      };
    };
    "30-br-nh-clients-vpn" = {
      netdevConfig = {
        Name = brClientsVpn;
        Kind = "bridge";
      };
    };
  };

  systemd.network.networks = {
    "20-br-cobalt-lan-30" = {
      matchConfig.Name = vlanClients;
      networkConfig.Bridge = brClients;
    };
    "20-br-cobalt-lan-31" = {
      matchConfig.Name = vlanClientsVpn;
      networkConfig.Bridge = brClientsVpn;
    };
    "30-br-nh-clients" = {
      matchConfig.Name = brClients;
      networkConfig = { };
    };
    "30-br-nh-clients-vpn" = {
      matchConfig.Name = brClientsVpn;
      networkConfig = { };
    };
  };

  systemd.services.nh-vap = {
    description = "Create Nighthawk 5GHz AP VAPs";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.iw ];
    script = ''
      nh_phy=$(cat /sys/class/net/wlan1/phy80211/name 2>/dev/null || echo ${nhPhy})
      for v in ${nhClients} ${nhClientsVpn}; do
        for _ in $(seq 1 30); do
          [ -d "/sys/class/net/$v" ] && break
          ${pkgs.iw}/bin/iw phy "$nh_phy" interface add "$v" type __ap 2>/dev/null || true
          sleep 1
        done
      done
    '';
  };

  systemd.services.nh-ap-conf = {
    description = "Generate Nighthawk hostapd configs";
    wantedBy = [ "multi-user.target" ];
    after = [ "sops-install-secrets.service" ];
    path = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.yq-go
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = hostapdConf;
      RuntimeDirectory = "nh-ap";
    };
  };

  systemd.services = {
    "nh-ap-${nhClients}" = (mkApUnit nhClients brClients "10.2.30.1").value;
    "nh-ap-${nhClientsVpn}" = (mkApUnit nhClientsVpn brClientsVpn "10.2.31.1").value;
  };
}
