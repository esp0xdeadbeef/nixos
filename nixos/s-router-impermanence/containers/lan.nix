{
  config,
  lib,
  pkgs,
  ...
}:
let
  iface = "ens21";
  vlan2 = "ens21.2";
  vlan2_adapter_name = "vlan2";
  vlan1337 = "ens21.1337";
  vlan1337_adapter_name = "vlan1337";
  ip_v4 = "192.168.50.1";

in
{
  networking.useNetworkd = true;
  networking.enableIPv6 = true;
  systemd.network.enable = true;

  # VLAN 2 on LAN interface

  # LAN interface config
  systemd.network.netdevs."10-${vlan2_adapter_name}" = {
    netdevConfig.Name = vlan2;
    netdevConfig.Kind = "vlan";
    vlanConfig.Id = 2;
  };

  systemd.network.netdevs."10-${vlan1337_adapter_name}" = {
    netdevConfig.Name = vlan1337;
    netdevConfig.Kind = "vlan";
    vlanConfig.Id = 1337;
  };

  systemd.network.networks."20-${iface}" = {
    matchConfig.Name = iface;
    linkConfig.RequiredForOnline = "no"; # parent has no IP
    networkConfig.VLAN = [
      vlan2
      vlan1337
    ];
  };

  # now configure VLAN1337 network
  systemd.network.networks."30-${vlan1337}" = {
    matchConfig.Name = vlan1337;
    address = [ "${ip_v4}/24" ];

    networkConfig = {
      DHCPPrefixDelegation = true;
      IPv6SendRA = true;
      IPv6AcceptRA = false;
    };

    ipv6SendRAConfig.EmitDNS = true;
  };

  # DHCPv4 via Kea
  systemd.services.kea-dhcp4 = {
    description = "Kea DHCPv4 Server";
    wantedBy = [ "multi-user.target" ];
    #requires = [ "vpn-ready.target" ];
    #after = [ "vpn-ready.target" ];
    path = [
      pkgs.kea
      pkgs.systemd
    ];
    unitConfig = {
      StartLimitIntervalSec = 0; # disables rate limiting
    };

    serviceConfig = {
      ExecStart = pkgs.writeShellScript "kea-dhcp4-execstart" ''
        set -euo pipefail
        set -x
        mkdir -p /var/run/kea || true
        ${pkgs.kea}/bin/kea-dhcp4 -c /etc/kea/kea-dhcp4.conf
      '';

      Type = "simple";
      Restart = "always"; # keep restarting no matter what
      RestartSec = 20; # 20s between attempts
      # your ExecStart, ExecStartPost, etc...
      ExecStartPost = pkgs.writeShellScript "kea-dhcp4-postcheck" ''
        set -euo pipefail


        # we should have a different way of checking if dhcp4 is working, this still sucks:

        LOG="$(${pkgs.systemd}/bin/journalctl -u kea-dhcp4 | tail -n 40)"

        if ! echo "$LOG" | ${pkgs.gnugrep}/bin/grep -q "listening on interface"; then
          echo "kea-dhcp4 not listening on any interface"
          exit 1
        fi

        sleep 3
        LOG="$(${pkgs.systemd}/bin/journalctl -u kea-dhcp4 -n 40)"
        if echo "$LOG" | ${pkgs.gnugrep}/bin/grep -q "DHCPSRV_OPEN_SOCKET_FAIL"; then
          echo "kea-dhcp4 failed to open sockets"
          exit 1
        fi

      '';

      # This ensures /run/kea/ exists with proper perms
      RuntimeDirectory = "kea";
      RuntimeDirectoryMode = "0755";
    };

    preStart = ''
      set -euo pipefail
      set -x
      mkdir -p /etc/kea || true
      mkdir -p /var/lib/kea || true
      chmod 700 /var/lib/kea
      IPV4_ADDR="${ip_v4}/24"

      # Get network details from sipcalc
      NETWORK_INFO=$(${pkgs.sipcalc}/bin/sipcalc "''${IPV4_ADDR}")

      PREFIX=$(echo "''${NETWORK_INFO}" | ${pkgs.gawk}/bin/awk -F- '/Network address/ {gsub(/ /,"",$2); print $2}')
      CIDR=$(echo "''${IPV4_ADDR}" | cut -d/ -f2)
      NETMASK=$(echo "''${NETWORK_INFO}" | ${pkgs.gawk}/bin/awk -F- '/Network mask[[:space:]]*-/ {gsub(/ /,"",$2); print $2}')
      GATEWAY=$(echo "''${IPV4_ADDR}" | ${pkgs.gnused}/bin/sed 's#/.*##')

      FIRST_HOST=$(echo "''${NETWORK_INFO}" | ${pkgs.gawk}/bin/awk '/Usable range/ {print $4}')
      LAST_HOST=$(echo "''${NETWORK_INFO}" | ${pkgs.gawk}/bin/awk '/Usable range/ {print $6}')
      POOL="''${FIRST_HOST}-''${LAST_HOST}"

      mkdir -p /etc/kea

      cat > /etc/kea/kea-dhcp4.conf <<EOF
      {
        "Dhcp4": {
          "valid-lifetime": 600,
          "renew-timer": 300,
          "rebind-timer": 540,
          "interfaces-config": {
            "interfaces": [ "${vlan1337}" ]
          },
          "lease-database": {
            "type": "memfile",
            "persist": true,
            "name": "/var/lib/kea/dhcp4.leases"
          },
          "subnet4": [
            {
              "id": 1,
              "subnet": "''${PREFIX}/''${CIDR}",
              "pools": [
                { "pool": "''${POOL}" }
              ],
              "option-data": [
                { "name": "routers", "data": "''${GATEWAY}" },
                { "name": "subnet-mask", "data": "''${NETMASK}" },
                { "name": "domain-name-servers", "data": "''${GATEWAY}" }
              ]
            }
          ]
        }
      }
      EOF
      # add the leases to the leases file:
      mkdir -p /var/lib/kea
      cat ${config.sops.secrets.lan-leases.path} > /var/lib/kea/dhcp4.leases

    '';
  };

  systemd.services.update_nftables_v4 = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "vpn-ready.target" ];
    after = [ "vpn-ready.target" ];

    path = [
      pkgs.jq
      pkgs.systemd
      pkgs.nftables
      pkgs.traceroute
      pkgs.gawk
      pkgs.util-linux
      pkgs.gron
      pkgs.jq
      pkgs.networkmanager
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 10;

      ExecStart = pkgs.writeShellScript "update_nftables_v4" ''
        set -euo pipefail
        set -x

        ${pkgs.nftables}/bin/nft flush table ip vpn 2>/dev/null || true

        # Discover current VPN IPv4 DNS endpoint
        #IPv4_DNS_VPN=$(${pkgs.networkmanager}/bin/nmcli connection show ${vlan1337_adapter_name} | grep 'ipv4.dns' | ${pkgs.gawk}/bin/awk '{print $2}' | head -n1)
        IPv4_DNS_VPN=$(${pkgs.networkmanager}/bin/nmcli -t -f all connection show ${vlan1337_adapter_name} | jq -Rn '[inputs | select(length>0) | split(":") | {(.[0]): (.[1])}] | add' | gron | grep '"ipv4.dns"' | gron -v)
        #IPv4_DNS_VPN=$(${pkgs.systemd}/bin/resolvectl -j show-server-state | jq -r ".[] | select(.Interface == \"${vlan1337_adapter_name}\").Server" | grep "\." | head -n1 || true)

        if [[ -z "$IPv4_DNS_VPN" || "$IPv4_DNS_VPN" == "--" ]]; then
          IPv4_DNS_VPN=$(${pkgs.traceroute}/bin/traceroute --interface=${vlan1337_adapter_name} -n4 -m 1 google.com | tail -n1 | ${pkgs.gawk}/bin/awk '{print $2}')
        fi

        echo "[update_nftables_v4] Using VPN DNS endpoint: $IPv4_DNS_VPN"

        # Generate ruleset directly with expanded variables
        tmpfile=$(mktemp)
        cat >"$tmpfile" <<NFT
        table ip vpn {
          chain prerouting {
            type nat hook prerouting priority dstnat; policy accept;
            iifname "${vlan2_adapter_name}" tcp dport 53 dnat to ${"$IPv4_DNS_VPN"}
            iifname "${vlan2_adapter_name}" udp dport 53 dnat to ${"$IPv4_DNS_VPN"}
          }

          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;
            ip saddr ${ip_v4} oifname "${vlan1337_adapter_name}" masquerade
          }

          chain mangle_forward {
            type filter hook forward priority mangle; policy accept;
            tcp flags syn tcp option maxseg size set rt mtu
          }

          chain forward {
            type filter hook forward priority 0; policy accept;
            iifname "${vlan2_adapter_name}" oifname "${vlan2_adapter_name}" accept
          }
        }
        NFT

        ${pkgs.nftables}/bin/nft -f "$tmpfile"
        rm -f "$tmpfile"

        echo "[update_nftables_v4] nftables ruleset applied successfully"
      '';
    };
  };

  # NAT (LAN → PPP)
  networking.nat.enable = true;

  #networking.nat.externalInterface = "ppp0";
  # temp setting so no disturbance:
  networking.nat.externalInterface = "10-vlan2";

  # wrong interface, but for testing:
  networking.nat.internalInterfaces = [ "10-vlan1337" ];

  # Firewall ports for LAN
  networking.firewall.enable = false;
  #networking.firewall.interfaces.${lan}.allowedUDPPorts = [
  #  53
  #  67
  #];
  sops.secrets.lan-leases = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

}
