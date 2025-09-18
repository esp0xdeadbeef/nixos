{
  config,
  pkgs,
  lib,
  ...
}:
{
  # 1. Secret VPN config loaded via SOPS
  sops.secrets."vpn-configuration" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  boot.kernelModules = [
    "vrf"
    "ip6table_nat"
  ];
  boot.kernel.sysctl = {
    "net.ipv4.tcp_l3mdev_accept" = 1;
    "net.ipv6.tcp_l3mdev_accept" = 1;
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # 2. Systemd target that signals when VPN is ready
  systemd.targets.vpn-ready = {
    description = "VPN interface is up and ready";
    wantedBy = [ "multi-user.target" ];
  };

  # 3. Decode VPN config at boot
  systemd.services.write-vpn-config = {
    description = "Decode VPN config from sops and write to /etc/vpn/tun0.conf";
    wantedBy = [ "network-pre.target" ];
    before = [ "network-online.target" ];
    after = [ "local-fs.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "write-vpn-config" ''
        set -euxo pipefail
        mkdir -p /etc/vpn
        secret_path="${config.sops.secrets."vpn-configuration".path}"
        if [ -f "$secret_path" ] && [ -s "$secret_path" ]; then
        cat "$secret_path" | ${pkgs.coreutils}/bin/base64 -d > /etc/vpn/tun0.conf
        chmod 600 /etc/vpn/tun0.conf
        else
        echo "[ERROR] VPN config secret missing or empty: $secret_path" >&2
        exit 1
        fi
      '';
    };
  };

  # 4. Dispatch VPN connection logic based on file content
  systemd.services.vpn-dispatcher = {
    description = "Continuously detect and start VPN tunnel (tun0), then start vpn-ready.target";
    after = [ "write-vpn-config.service" ];
    requires = [ "write-vpn-config.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple"; # Run continuously
      Restart = "always";
      RestartSec = 10;
      ExecStart = pkgs.writeShellScript "vpn-dispatcher-loop" ''
        set -euxo pipefail
        CONF=/etc/vpn/tun0.conf

        while true; do
          if grep -qE '^\[Interface\]' "$CONF"; then
            echo "[+] Detected WireGuard config"

            if ${pkgs.wireguard-tools}/bin/wg-quick up "$CONF"; then
              echo "[+] WireGuard tunnel up"
            else
              echo "[!] WireGuard failed, retrying in 10s"
              sleep 10
              continue
            fi

          elif grep -qE '^(client|dev|proto|remote)' "$CONF"; then
            echo "[+] Detected OpenVPN config"
            ${pkgs.openvpn}/bin/openvpn --config "$CONF" --daemon
            sleep 5  # give OpenVPN time to bring up the tunnel
          else
            echo "[!] Unknown VPN config format"
            sleep 10
            continue
          fi

          # Wait for interface to appear
          for i in $(seq 1 10); do
            if ip link show tun0 > /dev/null 2>&1; then
              echo "[+] Interface tun0 is up"
              break
            fi
            sleep 1
          done

          if ! ip link show tun0 > /dev/null 2>&1; then
            echo "[!] Interface tun0 never appeared, retrying"
            sleep 10
            continue
          fi

          # Signal readiness only once
          if [ ! -e /run/vpn-ready.once ]; then
            ${pkgs.systemd}/bin/systemctl start vpn-ready.target
            touch /run/vpn-ready.once
          fi

          # Wait indefinitely — or monitor VPN health
          sleep infinity
        done
      '';
    };
  };

  # 5. Example dependent service
  systemd.services.portforwards = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "vpn-ready.target" ];
    after = [ "vpn-ready.target" ];
    serviceConfig = {
      ExecStart = pkgs.writeShellScript "watchdog-networkmanager" ''
        set -euo pipefail
        set -x

        # Load subnet info (should set IPV4_VPN_SUBNET_STATIC_WITH_MASK and IPV6_VPN_SUBNET_STATIC_WITH_MASK)
        . /etc/root/subnets.sh

        # Extract prefixes from /CIDR notation
        IPV6_PREFIX=$(echo "$IPV6_VPN_SUBNET_STATIC_WITH_MASK" | cut -d/ -f1 | cut -d: -f1-3):
        IPV4_PREFIX=$(echo "$IPV4_VPN_SUBNET_STATIC_WITH_MASK" | cut -d/ -f1 | cut -d. -f1-3)

        # Format: [source_port]="last_octet:destination_port"
        declare -A HOSTS_IPV4=(
          [21612]="109:22"
          [21613]="167:80"
          [21614]="163:443"
        )

        # Format: [source_port]=":ipv6_suffix]:destination_port"
        declare -A HOSTS_IPV6=(
          [21612]=":a28f:aa25:f510:bdcb]:22"
          [21613]=":be24:11ff:fe3d:474d]:80"
          [21614]=":a133:c085:eeab:f2c1]:443"
        )

        for port in "''${!HOSTS_IPV4[@]}"; do
          # ----- IPv4 Parsing -----
          IFS=':' read -r ipv4_host dst_port_v4 <<< "''${HOSTS_IPV4[$port]}"
          dst_port_v4="''${dst_port_v4:-$port}"

          # ----- IPv6 Parsing -----
          raw_ipv6_entry="''${HOSTS_IPV6[$port]}"
          dst_port_v6="''${raw_ipv6_entry##*:}"                    # after last :
          ipv6_host_suffix="''${raw_ipv6_entry%]:$dst_port_v6}"    # remove ]:<port>
          ipv6_host_suffix="''${ipv6_host_suffix#:}"              # strip leading :

          # ----- Rules -----

          # IPv4 rule
          ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -i tun0 -p tcp --dport "$port" \
            -j DNAT --to-destination "$IPV4_PREFIX.$ipv4_host:$dst_port_v4"

          # IPv6 rule
          ${pkgs.iptables}/bin/ip6tables -t nat -A PREROUTING -i tun0 -p tcp --dport "$port" \
            -j DNAT --to-destination "[$IPV6_PREFIX:$ipv6_host_suffix]:$dst_port_v6"
        done
      '';
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  systemd.services.watchdog-networkmanager = {
    description = "Watchdog for VPN interface and NetworkManager recovery";
    wantedBy = [ "multi-user.target" ];
    requires = [ "vpn-ready.target" ];
    after = [ "vpn-ready.target" ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 5;

      ExecStart = pkgs.writeShellScript "watchdog-networkmanager" ''
        #!/usr/bin/env bash
        set -euo pipefail

        interface="tun0"
        check_interval=100

        while true; do
          if [[ ! -d "/sys/class/net/$interface" ]]; then
            echo "[$(date)] Interface $interface not found. Restarting NetworkManager..."
            ${pkgs.systemd}/bin/systemctl restart NetworkManager
            sleep 3
            continue
          fi

          rx_path="/sys/class/net/$interface/statistics/rx_bytes"
          if [[ ! -r "$rx_path" ]]; then
            echo "[$(date)] Cannot read RX stats from $rx_path. Restarting NetworkManager..."
            ${pkgs.systemd}/bin/systemctl restart NetworkManager
            sleep 3
            continue
          fi

          RX_BEFORE=$(cat "$rx_path")
          sleep "$check_interval"
          RX_AFTER=$(cat "$rx_path")

          if [[ "$RX_BEFORE" -eq "$RX_AFTER" ]]; then
            echo "[$(date)] No RX activity on $interface. Probing with ping..."
            if ! ${pkgs.iputils}/bin/ping -c1 -I "$interface" -W 2 8.8.8.8 >/dev/null 2>&1; then
              echo "[$(date)] Ping failed. Restarting NetworkManager..."
              ${pkgs.systemd}/bin/systemctl restart NetworkManager
              sleep 3
            else
              echo "[$(date)] Ping succeeded, probably idle."
            fi
          else
            echo "[$(date)] RX changed: $RX_BEFORE → $RX_AFTER. OK."
          fi
        done
      '';
    };
  };

  systemd.services.update_iptables = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "vpn-ready.target" ];
    after = [ "vpn-ready.target" ];
    path = [ pkgs.networkmanager ];
    serviceConfig = {
      ExecStart = pkgs.writeShellScript "update_iptables" ''
        set -euo pipefail
        # set -x
        # Get the current IP address of tun0
        source /etc/root/subnets.sh

        IPv4_DNS_VPN=$(${pkgs.networkmanager}/bin/nmcli connection show tun0 | grep 'ipv4.dns' | ${pkgs.gawk}/bin/awk '{print $2}' | head -n1)
        IPv6_DNS_VPN=$(${pkgs.networkmanager}/bin/nmcli connection show tun0 | grep 'ipv6.dns' | ${pkgs.gawk}/bin/awk '{print $2}' | head -n1)

        IPv6_INTERFACE_NATTED_LAN=$(${pkgs.iproute2}/bin/ip -6 a s ens20 | grep 'scope global noprefixroute' | ${pkgs.gawk}/bin/awk '{print $2}' | cut -d '/' -f 1)
        IPv6_INTERFACE_NATTED_LAN_WITH_SUBNET=$(${pkgs.iproute2}/bin/ip -6 a s ens20 | grep 'scope global noprefixroute' | ${pkgs.gawk}/bin/awk '{print $2}')

        if [[ -z "$IPv4_DNS_VPN" || "$IPv4_DNS_VPN" == "--" ]]; then
            # If it's empty or has '--', get the first hop's IPv4 address from traceroute and assign it to IPv4_DNS_VPN
            IPv4_DNS_VPN=$(${pkgs.traceroute}/bin/traceroute --interface=tun0 -n4 -m 1 google.com | tail -n1 | ${pkgs.gawk}/bin/awk '{print $2}')
            echo "IPV4 Tunnel IP: $IPv4_DNS_VPN"
        fi

        # Check if the DNS setting is empty or if it contains '--'
        if [[ -z "$IPv6_DNS_VPN" || "$IPv6_DNS_VPN" == "--" ]]; then
            # If it's empty or has '--', get the first hop's IPv6 address from traceroute and assign it to IPv6_DNS_VPN
            IPv6_DNS_VPN=$(${pkgs.traceroute}/bin/traceroute --interface=tun0 -n6 -m 1 google.com | tail -n1 | ${pkgs.gawk}/bin/awk '{print $2}')
            echo "IPV6 Tunnel IP: $IPv6_DNS_VPN"
        fi

        # logging for DNS:
        echo "IPv4_DNS_VPN: $IPv4_DNS_VPN"
        echo "IPv6_DNS_VPN: $IPv6_DNS_VPN"


        # Flush old rules for port 53 forwarding
        ${pkgs.iptables}/bin/iptables -t nat -D PREROUTING -i ens20 -p udp --dport 53 -j DNAT --to-destination $IPv4_DNS_VPN || true
        ${pkgs.iptables}/bin/iptables -t nat -D PREROUTING -i ens20 -p tcp --dport 53 -j DNAT --to-destination $IPv4_DNS_VPN || true
        # Allow forwarding to self
        ${pkgs.iptables}/bin/iptables -I FORWARD -i ens20 -o ens20 -j ACCEPT
        # Portforwards DNS
        ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -i ens20 -p udp --dport 53 -j DNAT --to-destination $IPv4_DNS_VPN
        ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -i ens20 -p tcp --dport 53 -j DNAT --to-destination $IPv4_DNS_VPN
        # MASQUERADE the traffic from IPV4_VPN_SUBNET_STATIC_WITH_MASK to tun0
        ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s $IPV4_VPN_SUBNET_STATIC_WITH_MASK -o tun0 -j MASQUERADE


        # Flush old rules for port 53 forwarding
        ${pkgs.iptables}/bin/ip6tables -t nat -D PREROUTING -i ens20 -p udp --dport 53 -j DNAT --to-destination $IPv6_DNS_VPN || true
        ${pkgs.iptables}/bin/ip6tables -t nat -D PREROUTING -i ens20 -p tcp --dport 53 -j DNAT --to-destination $IPv6_DNS_VPN || true

        # allow callbacks on the adapter itself
        ${pkgs.iptables}/bin/ip6tables -I FORWARD -i ens20 -o ens20 -j ACCEPT
        # Add new rules with the current IP address
        ${pkgs.iptables}/bin/ip6tables -t nat -A PREROUTING -i ens20 -p udp --dport 53 -j DNAT --to-destination $IPv6_DNS_VPN
        ${pkgs.iptables}/bin/ip6tables -t nat -A PREROUTING -i ens20 -p tcp --dport 53 -j DNAT --to-destination $IPv6_DNS_VPN

        # DNAT any incoming UDP or TCP DNS on ens20 to the real VPN DNS server
        ${pkgs.iptables}/bin/ip6tables -t nat -A PREROUTING -i ens20 -p udp --dport 53 -d $IPv6_INTERFACE_NATTED_LAN -j DNAT --to-destination "[$IPv6_DNS_VPN]:53"
        ${pkgs.iptables}/bin/ip6tables -t nat -A PREROUTING -i ens20 -p tcp --dport 53 -d $IPv6_INTERFACE_NATTED_LAN -j DNAT --to-destination "[$IPv6_DNS_VPN]:53"
        ${pkgs.iptables}/bin/ip6tables -A FORWARD -i ens20 -o tun0 -p udp --dport 53 -d $IPv6_DNS_VPN -j ACCEPT
        ${pkgs.iptables}/bin/ip6tables -A FORWARD -i ens20 -o tun0 -p tcp --dport 53 -d $IPv6_DNS_VPN -j ACCEPT

        # All traffic from LAN to VPN
        ${pkgs.iptables}/bin/ip6tables -A FORWARD -i ens20 -o tun0 -s $IPv6_INTERFACE_NATTED_LAN_WITH_SUBNET -j ACCEPT

        # Return traffic
        ${pkgs.iptables}/bin/ip6tables -A FORWARD -i tun0 -o ens20 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

        # Accept return traffic
        ${pkgs.iptables}/bin/ip6tables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
        ${pkgs.iptables}/bin/ip6tables -t nat -A POSTROUTING -s $IPv6_INTERFACE_NATTED_LAN_WITH_SUBNET -o tun0 -j MASQUERADE


        # MSS clamping (mtu size forcing) 
        ${pkgs.iptables}/bin/iptables -t mangle -A FORWARD -o tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
        ${pkgs.iptables}/bin/ip6tables -t mangle -A FORWARD -o tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu'';
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  systemd.services.kea-dhcp4 = {
    description = "Kea DHCPv4 Server";
    wantedBy = [ "multi-user.target" ];
    requires = [ "vpn-ready.target" ];
    after = [ "vpn-ready.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.kea}/bin/kea-dhcp4 -c /etc/kea/kea-dhcp4.conf";
      Type = "simple";
      Restart = "on-failure";
      RestartSec = 1;
      ExecStartPost = pkgs.writeShellScript "kea-dhcp4-postcheck" ''
      set -euo pipefail

      LOG="$(${pkgs.systemd}/bin/journalctl -u kea-dhcp4 -n 50)"

      if echo "$LOG" | ${pkgs.gnugrep}/bin/grep -q "DHCPSRV_OPEN_SOCKET_FAIL"; then
        echo "kea-dhcp4 failed to open sockets"
        exit 1
      fi

      if ! echo "$LOG" | ${pkgs.gnugrep}/bin/grep -q "listening on interface"; then
        echo "kea-dhcp4 not listening on any interface"
        exit 1
      fi
    '';


      # This ensures /run/kea/ exists with proper perms
      RuntimeDirectory = "kea";
      RuntimeDirectoryMode = "0755";
    };

    preStart = ''
      set -euo pipefail
      mkdir -p /etc/kea || true
      mkdir -p /var/lib/kea || true
      chmod 700 /var/lib/kea
      source /etc/root/subnets.sh
      IPV4_ADDR="''${IPV4_VPN_SUBNET_STATIC_WITH_MASK}"

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
            "interfaces": [ "ens20" ]
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
    '';
  };

  systemd.services.radvd = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "vpn-ready.target" ];
    after = [ "vpn-ready.target" ];
    path = [ pkgs.radvd ];

    serviceConfig = {
      ExecStart = "${pkgs.radvd}/bin/radvd -n -C /root/radvd.conf ens20";
      Restart = "on-failure";
      RestartSec = 10;
      # StartLimitIntervalSec = 0;
      StartLimitBurst = 0;
    };

    preStart = ''
      echo "Generating radvd.conf..."
      set -euo pipefail

      # Extract IPv6 address and subnet prefix for ens20
      IPV6_ADDR=$(${pkgs.iproute2}/bin/ip -6 a s ens20 | grep 'scope global' | ${pkgs.gawk}/bin/awk '{print $2}')

      source /etc/root/subnets.sh
      IPV6_ADDR=$IPV6_VPN_SUBNET_STATIC_WITH_MASK

      PREFIX=$(${pkgs.sipcalc}/bin/sipcalc "$IPV6_ADDR")
      PREFIX=$(${pkgs.sipcalc}/bin/sipcalc "$IPV6_ADDR" | grep 'Subnet prefix' | ${pkgs.gawk}/bin/awk '{print $5}')
      IPV6_ADDR_WITHOUT_MASK=$(echo $IPV6_ADDR | sed 's/\/.*//g')
      echo -n 'interface ens20 {
        AdvSendAdvert on;
        MinRtrAdvInterval 3;
        MaxRtrAdvInterval 10;
        RDNSS '$IPV6_ADDR_WITHOUT_MASK' {
                AdvRDNSSLifetime 800;
        };
        prefix '$PREFIX' {
          AdvOnLink on;
          AdvAutonomous on;
          AdvRouterAddr on;
        };
      };' | tee /root/radvd.conf
      chmod 644 /root/radvd.conf
    '';
  };

  environment.systemPackages = with pkgs; [
    # coreutils
    # python3
    # coreutils
    # openvpn
    # wireguard-tools
    tcpdump
  ];


  networking.networkmanager.enable = true;
  networking.networkmanager.unmanaged = [ ];

  environment.etc = {
    "root/subnets.sh" = {
      source = pkgs.writeShellScript "subnets" ''
        export IPV4_VPN_SUBNET_STATIC_WITH_MASK="10.90.0.1/24"
        export IPV6_VPN_SUBNET_STATIC_WITH_MASK="fd90:dead:beef::100/64"
      '';
      mode = "0755";
    };

    "NetworkManager/system-connections/ens18.nmconnection" = {
      text = ''
        [connection]
        id=ens18
        type=ethernet
        interface-name=ens18
        autoconnect=true
        permissions=

        [ipv4]
        method=auto
        route-metric=300
        ignore-auto-dns=true
        never-default=true

        [ipv6]
        method=auto
        route-metric=300
        ignore-auto-dns=true
        never-default=true
      '';
      mode = "0600";
    };

    "NetworkManager/system-connections/ens19.nmconnection" = {
      text = ''
        [connection]
        id=ens19
        type=ethernet
        interface-name=ens19
        autoconnect=true
        permissions=

        [ipv4]
        method=auto
        route-metric=100
        ignore-auto-dns=false

        [ipv6]
        method=auto
        route-metric=100
        ignore-auto-dns=false
      '';
      mode = "0600";
    };

    "NetworkManager/system-connections/ens20.nmconnection" = {
      text = ''
        [connection]
        id=ens20
        type=ethernet
        interface-name=ens20
        autoconnect=true
        permissions=

        [ipv4]
        method=manual
        address1=10.90.0.1/24
        route-metric=250
        ignore-auto-dns=true

        [ipv6]
        method=manual
        address1=fd90:dead:beef::100/64
        route-metric=250
        ignore-auto-dns=true
      '';
      mode = "0600";
    };
  };


  networking.useNetworkd = true;

  # Disable networkd-wait-online
  systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;
}
