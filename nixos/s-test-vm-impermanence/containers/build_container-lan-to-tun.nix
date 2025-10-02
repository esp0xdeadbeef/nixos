{
  config,
  pkgs,
  lib,
  ...
}:

let
  # management_interface = "ens18";
  upstream_VPN_interface = "wan";
  vpnNATInterface = "lan";

  vpnInterface = "tun0";
  vpnConfBasePath = "/etc/vpn";
  vpnConfPath = "${vpnConfBasePath}/${vpnInterface}.conf";
  vpnIPv4WithMask = "10.90.0.1/24";
  vpnIPv6WithMask = "fd90:dead:beef::100/64";

  # Flip this when you want VRF mode
  enableVRF = false;

  # ignore this
  vrf_table_vpn = 10;
  vrf_name_vpn = "vrf-vpn";

  vrf_patch = if enableVRF then "${pkgs.iproute2}/bin/ip vrf exec ${vrf_name_vpn}" else "";
in
{
  system.stateVersion = "25.05";

  networking.useHostResolvConf = lib.mkForce false;
  services.resolved.enable = true;
  networking.useDHCP = lib.mkDefault false;
  networking.interfaces.wan.useDHCP = true;

  networking.interfaces.lan.ipv4.addresses = [
    {
      address = "10.90.0.1";
      prefixLength = 24;
    }
  ];
  networking.networkmanager.enable = true;

  systemd.slices.vrf = lib.mkIf enableVRF {
    description = "Slice for VRF-routed services";
  };

  systemd.network.networks."40-nat-iface" = lib.mkIf enableVRF {
    matchConfig.Name = vpnNATInterface;
    networkConfig = {
      VRF = vrf_name_vpn;
      DHCP = "no";
      Address = [
        vpnIPv4WithMask
        vpnIPv6WithMask
      ];
    };
  };

  # 1. Secret VPN config loaded via SOPS
  # sops.secrets."vpn-configuration" = {
  #   owner = "root";
  #   group = "root";
  #   mode = "0400";
  # };

  # check if these are required (not done yet.)
  boot.kernelModules = [
    "vrf"
    "ip6table_nat"
  ];
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv4.tcp_l3mdev_accept" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # 2. Systemd target that signals when VPN is ready
  systemd.targets.vpn-ready = {
    description = "VPN interface is up and ready";
    wantedBy = [ "multi-user.target" ];
  };

  # 3. Decode VPN config at boot
  systemd.services.write-vpn-config = {
    description = "Decode VPN config from sops and write to ${vpnConfPath}";
    wantedBy = [ "network-pre.target" ];
    before = [ "network-online.target" ];
    after = [ "local-fs.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "write-vpn-config" ''
        set -euxo pipefail
        echo 'depricated (already in the folder)'
      '';
    };
  };

  systemd.services."nftables-vrf-mark" = lib.mkIf enableVRF {
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.nftables
      pkgs.coreutils
      pkgs.gawk
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "nftables-vrf-mark" ''
        set -eux

        # Ensure table/chain exist
        nft list table inet vrf >/dev/null 2>&1 || nft add table inet vrf
        nft list chain inet vrf output >/dev/null 2>&1 || \
          nft add chain inet vrf output '{ type filter hook output priority 0; }'

        # Grab inode ID for vrf.slice
        CGROUP_ID=$(stat -c %i /sys/fs/cgroup/vrf.slice)
        echo "[*] vrf.slice cgroup id = $CGROUP_ID"

        # Remove old rule if present
        RULE_HANDLE=$(nft -a list chain inet vrf output | awk '/meta cgroup '"$CGROUP_ID"'/ {print $NF}')
        if [ -n "$RULE_HANDLE" ]; then
          nft delete rule inet vrf output handle "$RULE_HANDLE" || true
        fi

        # Add rule: mark all traffic from vrf.slice
        nft add rule inet vrf output meta cgroup "$CGROUP_ID" meta mark set 0x1
      '';
    };
  };
  systemd.services.vpn-dispatcher = {
    description = "Continuously detect and start VPN tunnel (${vpnInterface}), then start vpn-ready.target";
    after = [
      "write-vpn-config.service"
      "systemd-networkd.service"
    ];
    requires = [
      "write-vpn-config.service"
      "systemd-networkd.service"
    ];
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [
      iproute2
      coreutils
      gawk
      wireguard-tools
      openvpn
      systemd
      nftables
    ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 10;
      Slice = lib.mkIf enableVRF "vrf.slice";

      ExecStart = pkgs.writeShellScript "vpn-dispatcher-loop" ''
        set -euxo pipefail
        CONF=${vpnConfPath}
        VRF_TABLE=${toString vrf_table_vpn}
        VRF_NAME=${vrf_name_vpn}

        while true; do
          if grep -q "^ *${vpnInterface}:" /proc/net/dev; then
            echo "[*] ${vpnInterface} already exists, skipping setup"
          else
            ${lib.optionalString enableVRF ''
              echo "[*] Waiting for ${upstream_VPN_interface} to settle..."
              for i in $(seq 1 20); do
                ip addr show dev ${upstream_VPN_interface} | grep -q "inet" && break || true
                sleep 1
              done

              # Snapshot BEFORE
              ip route show table main | sort -u > /run/routes.before
              ip -6 route show table main | sort -u > /run/routes6.before
              ip rule show | awk '{prio=$1; $1=""; sub(/^ /,""); print prio":"$0}' | sort -n > /run/rules.before

              # === Add killswitch ===
              echo "[*] Enabling temporary egress block (except mgmt + loopback)"
              nft add table inet vpnblock
              nft add chain inet vpnblock output { type filter hook output priority -100\; policy drop; }
              # Always allow established/related so existing SSH doesn’t die instantly
              nft add rule inet vpnblock output ct state established,related accept
              # Allow anything on loopback
              nft add rule inet vpnblock output oif lo accept
              # Allow anything going out management interface
              nft add rule inet vpnblock output oifname ''${MGMT_IF} accept
            ''}

            if grep -qE '^\[Interface\]' "''${CONF}"; then
              echo "[+] Detected WireGuard config"
              ${vrf_patch} wg-quick up "''${CONF}"
            elif grep -qE '^(client|dev|proto|remote)' "''${CONF}"; then
              echo "[+] Detected OpenVPN config"
              ${vrf_patch} openvpn --config "''${CONF}" --daemon
              sleep 2
            else
              echo "[!] Unknown VPN config format"
              ${lib.optionalString enableVRF "nft delete table inet vpnblock || true"}
              sleep 10
              continue
            fi

            ${lib.optionalString enableVRF ''
              # Snapshot AFTER
              ip route show table main | sort -u > /run/routes.after
              ip -6 route show table main | sort -u > /run/routes6.after
              ip rule show | awk '{prio=$1; $1=""; sub(/^ /,""); print prio":"$0}' | sort -n > /run/rules.after

              # Diff IPv4 routes
              comm -13 /run/routes.before /run/routes.after | while read -r line; do
                [ -n "$line" ] || continue
                echo "[+] Migrating IPv4 route: $line"
                ip route add $line table "''${VRF_TABLE}" || true
                ip route del $line || true
              done

              # Diff IPv6 routes
              comm -13 /run/routes6.before /run/routes6.after | while read -r line; do
                [ -n "$line" ] || continue
                echo "[+] Migrating IPv6 route: $line"
                ip -6 route add $line table "''${VRF_TABLE}" || true
                ip -6 route del $line || true
              done

              # Diff rules
              comm -13 /run/rules.before /run/rules.after | while IFS= read -r rule; do
                [ -n "$rule" ] || continue
                echo "[+] Processing new rule: $rule"
                if [[ "$rule" =~ ^([0-9]+):(.*) ]]; then
                  PRIO="''${BASH_REMATCH[1]}"
                  REST="''${BASH_REMATCH[2]}"
                else
                  continue
                fi

                REST=$(echo "$REST" | xargs)
                [ -z "$REST" ] && continue

                if echo "$REST" | grep -q "table main"; then
                  NEWREST="''${REST/main/''${VRF_TABLE}}"
                elif echo "$REST" | grep -q "table 51820"; then
                  NEWREST="''${REST/51820/''${VRF_TABLE}}"
                else
                  NEWREST="$REST"
                fi

                ip rule add priority "$PRIO" $NEWREST || true
                ip rule del priority "$PRIO" || true
              done

              # === Remove killswitch ===
              echo "[*] Removing temporary egress block"
              nft delete table inet vpnblock || true
            ''}
          fi

          ${lib.optionalString enableVRF ''
            echo "[*] Ensuring ${vpnInterface} is enslaved to VRF ''${VRF_NAME}"
            current_master=$(readlink "/sys/class/net/${vpnInterface}/master" || echo "")
            if [[ "$current_master" != *"''${VRF_NAME}"* ]]; then
              ip link set ${vpnInterface} master ''${VRF_NAME}
              ip link set ${vpnInterface} up
            fi
          ''}

          if [ ! -e /run/vpn-ready.once ]; then
            systemctl start vpn-ready.target
            touch /run/vpn-ready.once
          fi

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

        # Load subnet info (should set ${vpnIPv4WithMask} and ${vpnIPv6WithMask})
        . /etc/root/subnets.sh

        # Extract prefixes from /CIDR notation
        IPV6_PREFIX=$(echo "${vpnIPv6WithMask}" | cut -d/ -f1 | cut -d: -f1-3):
        IPV4_PREFIX=$(echo "${vpnIPv4WithMask}" | cut -d/ -f1 | cut -d. -f1-3)

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
          ${vrf_patch} ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -i ${vpnInterface} -p tcp --dport "$port" \
            -j DNAT --to-destination "$IPV4_PREFIX.$ipv4_host:$dst_port_v4"

          # IPv6 rule
          ${vrf_patch} ${pkgs.iptables}/bin/ip6tables -t nat -A PREROUTING -i ${vpnInterface} -p tcp --dport "$port" \
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

        interface="${vpnInterface}"
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

  systemd.services.update_iptables_v4 = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "vpn-ready.target" ];
    after = [ "vpn-ready.target" ];
    path = [ pkgs.networkmanager ];
    serviceConfig = {
      ExecStart = pkgs.writeShellScript "update_iptables_v4" ''
        set -euo pipefail
        set -x
        # Get the current IP address of ${vpnInterface}
        source /etc/root/subnets.sh

        # IPv4_DNS_VPN=$(${pkgs.networkmanager}/bin/nmcli connection show ${vpnInterface} | grep 'ipv4.dns' | ${pkgs.gawk}/bin/awk '{print $2}' | head -n1)
        # IPv4_DNS_VPN=$(${pkgs.systemd}/bin/resolvectl dns "${vpnInterface}"  | cut -d ':' -f 2 | ${pkgs.util-linux}/bin/rev | ${pkgs.gawk}/bin/awk '{print $2; exit}' | ${pkgs.util-linux}/bin/rev)
        IPv4_DNS_VPN=$(${pkgs.systemd}/bin/resolvectl dns "${vpnInterface}" | ${pkgs.util-linux}/bin/rev | ${pkgs.gawk}/bin/awk '{print $2; exit}' | ${pkgs.util-linux}/bin/rev)
        if [[ -z "$IPv4_DNS_VPN" || "$IPv4_DNS_VPN" == "--" ]]; then
            # If it's empty or has '--', get the first hop's IPv4 address from traceroute and assign it to IPv4_DNS_VPN
            IPv4_DNS_VPN=$(${pkgs.traceroute}/bin/traceroute --interface=${vpnInterface} -n4 -m 1 google.com | tail -n1 | ${pkgs.gawk}/bin/awk '{print $2}')
            echo "IPV4 Tunnel IP: $IPv4_DNS_VPN"
        fi

        # logging for DNS:
        echo "IPv4_DNS_VPN: $IPv4_DNS_VPN"

        # Flush old rules for port 53 forwarding
        ${vrf_patch} ${pkgs.iptables}/bin/iptables -t nat -D PREROUTING -i ${vpnNATInterface} -p udp --dport 53 -j DNAT --to-destination $IPv4_DNS_VPN || true
        ${vrf_patch} ${pkgs.iptables}/bin/iptables -t nat -D PREROUTING -i ${vpnNATInterface} -p tcp --dport 53 -j DNAT --to-destination $IPv4_DNS_VPN || true
        # Allow forwarding to self
        ${vrf_patch} ${pkgs.iptables}/bin/iptables -I FORWARD -i ${vpnNATInterface} -o ${vpnNATInterface} -j ACCEPT
        # Portforwards DNS
        ${vrf_patch} ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -i ${vpnNATInterface} -p udp --dport 53 -j DNAT --to-destination $IPv4_DNS_VPN
        ${vrf_patch} ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -i ${vpnNATInterface} -p tcp --dport 53 -j DNAT --to-destination $IPv4_DNS_VPN
        # MASQUERADE the traffic from ${vpnIPv4WithMask} to ${vpnInterface}
        ${vrf_patch} ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s ${vpnIPv4WithMask} -o ${vpnInterface} -j MASQUERADE
        # MSS clamping (mtu size forcing) 
        ${vrf_patch} ${pkgs.iptables}/bin/iptables -t mangle -A FORWARD -o ${vpnInterface} -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu


      '';
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
  systemd.services.update_iptables_v6 = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "vpn-ready.target" ];
    after = [ "vpn-ready.target" ];
    path = [ pkgs.networkmanager ];
    serviceConfig = {
      ExecStart = pkgs.writeShellScript "update_iptables_v6" ''
        set -euo pipefail
        set -x
        # Get the current IP address of ${vpnInterface}
        source /etc/root/subnets.sh

        # IPv6_DNS_VPN=$(${pkgs.networkmanager}/bin/nmcli connection show ${vpnInterface} | grep 'ipv6.dns' | ${pkgs.gawk}/bin/awk '{print $2}' | head -n1)
        IPv6_DNS_VPN=$(${pkgs.systemd}/bin/resolvectl dns "${vpnInterface}" | ${pkgs.util-linux}/bin/rev | ${pkgs.gawk}/bin/awk '{print $1; exit}' | ${pkgs.util-linux}/bin/rev)

        IPv6_INTERFACE_NATTED_LAN=$(${pkgs.iproute2}/bin/ip -6 a s ${vpnNATInterface} | grep 'scope global noprefixroute' | ${pkgs.gawk}/bin/awk '{print $2}' | cut -d '/' -f 1)
        IPv6_INTERFACE_NATTED_LAN_WITH_SUBNET=$(${pkgs.iproute2}/bin/ip -6 a s ${vpnNATInterface} | grep 'scope global noprefixroute' | ${pkgs.gawk}/bin/awk '{print $2}')


        # Check if the DNS setting is empty or if it contains '--'
        if [[ -z "$IPv6_DNS_VPN" || "$IPv6_DNS_VPN" == "--" ]]; then
            # If it's empty or has '--', get the first hop's IPv6 address from traceroute and assign it to IPv6_DNS_VPN
            IPv6_DNS_VPN=$(${pkgs.traceroute}/bin/traceroute --interface=${vpnInterface} -n6 -m 1 google.com | tail -n1 | ${pkgs.gawk}/bin/awk '{print $2}')
            echo "IPV6 Tunnel IP: $IPv6_DNS_VPN"
        fi

        # logging for DNS:
        echo "IPv6_DNS_VPN: $IPv6_DNS_VPN"



        # Flush old rules for port 53 forwarding
        ${vrf_patch} ${pkgs.iptables}/bin/ip6tables -t nat -D PREROUTING -i ${vpnNATInterface} -p udp --dport 53 -j DNAT --to-destination $IPv6_DNS_VPN || true
        ${vrf_patch} ${pkgs.iptables}/bin/ip6tables -t nat -D PREROUTING -i ${vpnNATInterface} -p tcp --dport 53 -j DNAT --to-destination $IPv6_DNS_VPN || true

        # allow callbacks on the adapter itself
        ${vrf_patch} ${pkgs.iptables}/bin/ip6tables -I FORWARD -i ${vpnNATInterface} -o ${vpnNATInterface} -j ACCEPT
        # Add new rules with the current IP address
        ${vrf_patch} ${pkgs.iptables}/bin/ip6tables -t nat -A PREROUTING -i ${vpnNATInterface} -p udp --dport 53 -j DNAT --to-destination $IPv6_DNS_VPN
        ${vrf_patch} ${pkgs.iptables}/bin/ip6tables -t nat -A PREROUTING -i ${vpnNATInterface} -p tcp --dport 53 -j DNAT --to-destination $IPv6_DNS_VPN

        # DNAT any incoming UDP or TCP DNS on ${vpnNATInterface} to the real VPN DNS server
        ${vrf_patch} ${pkgs.iptables}/bin/ip6tables -t nat -A PREROUTING -i ${vpnNATInterface} -p udp --dport 53 -d $IPv6_INTERFACE_NATTED_LAN -j DNAT --to-destination "[$IPv6_DNS_VPN]:53"
        ${vrf_patch} ${pkgs.iptables}/bin/ip6tables -t nat -A PREROUTING -i ${vpnNATInterface} -p tcp --dport 53 -d $IPv6_INTERFACE_NATTED_LAN -j DNAT --to-destination "[$IPv6_DNS_VPN]:53"
        ${vrf_patch} ${pkgs.iptables}/bin/ip6tables -A FORWARD -i ${vpnNATInterface} -o ${vpnInterface} -p udp --dport 53 -d $IPv6_DNS_VPN -j ACCEPT
        ${vrf_patch} ${pkgs.iptables}/bin/ip6tables -A FORWARD -i ${vpnNATInterface} -o ${vpnInterface} -p tcp --dport 53 -d $IPv6_DNS_VPN -j ACCEPT

        # All traffic from LAN to VPN
        ${vrf_patch} ${pkgs.iptables}/bin/ip6tables -A FORWARD -i ${vpnNATInterface} -o ${vpnInterface} -s $IPv6_INTERFACE_NATTED_LAN_WITH_SUBNET -j ACCEPT

        # Return traffic
        ${vrf_patch} ${pkgs.iptables}/bin/ip6tables -A FORWARD -i ${vpnInterface} -o ${vpnNATInterface} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

        # Accept return traffic
        ${vrf_patch} ${pkgs.iptables}/bin/ip6tables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
        ${vrf_patch} ${pkgs.iptables}/bin/ip6tables -t nat -A POSTROUTING -s $IPv6_INTERFACE_NATTED_LAN_WITH_SUBNET -o ${vpnInterface} -j MASQUERADE


        ${vrf_patch} ${pkgs.iptables}/bin/ip6tables -t mangle -A FORWARD -o ${vpnInterface} -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
      '';
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
      ExecStart = pkgs.writeShellScript "kea-dhcp4-execstart" ''
        set -euo pipefail
        set -x
        mkdir -p /var/run/kea || true
        ${pkgs.kea}/bin/kea-dhcp4 -c /etc/kea/kea-dhcp4.conf
      '';

      Type = "simple";
      Restart = "on-failure";
      RestartSec = 1;
      ExecStartPost = pkgs.writeShellScript "kea-dhcp4-postcheck" ''
        set -euo pipefail


        # we should have a different way of checking if dhcp4 is working:

        # LOG="$(${pkgs.systemd}/bin/journalctl -u kea-dhcp4 -n 40)"

        # if ! echo "$LOG" | ${pkgs.gnugrep}/bin/grep -q "listening on interface"; then
        #   echo "kea-dhcp4 not listening on any interface"
        #   exit 1
        # fi

        # sleep 3
        # LOG="$(${pkgs.systemd}/bin/journalctl -u kea-dhcp4 -n 40)"
        # if echo "$LOG" | ${pkgs.gnugrep}/bin/grep -q "DHCPSRV_OPEN_SOCKET_FAIL"; then
        #   echo "kea-dhcp4 failed to open sockets"
        #   exit 1
        # fi

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
      source /etc/root/subnets.sh
      IPV4_ADDR="${vpnIPv4WithMask}"

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
            "interfaces": [ "${vpnNATInterface}" ]
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
      ExecStart = "${vrf_patch} ${pkgs.radvd}/bin/radvd -n -C /root/radvd.conf ${vpnNATInterface}";
      Restart = "on-failure";
      RestartSec = 10;
      # StartLimitIntervalSec = 0;
      StartLimitBurst = 0;
    };

    preStart = ''
      echo "Generating radvd.conf..."
      set -euo pipefail

      # Extract IPv6 address and subnet prefix for ${vpnNATInterface}
      IPV6_ADDR=$(${pkgs.iproute2}/bin/ip -6 a s ${vpnNATInterface} | grep 'scope global' | ${pkgs.gawk}/bin/awk '{print $2}')

      source /etc/root/subnets.sh
      IPV6_ADDR=${vpnIPv6WithMask}

      PREFIX=$(${pkgs.sipcalc}/bin/sipcalc "$IPV6_ADDR")
      PREFIX=$(${pkgs.sipcalc}/bin/sipcalc "$IPV6_ADDR" | grep 'Subnet prefix' | ${pkgs.gawk}/bin/awk '{print $5}')
      IPV6_ADDR_WITHOUT_MASK=$(echo $IPV6_ADDR | sed 's/\/.*//g')
      echo -n 'interface ${vpnNATInterface} {
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

  # environment.systemPackages = with pkgs; [
  #   # coreutils
  #   # python3
  #   # coreutils
  #   dnsutils # dig
  #   openvpn
  #   wireguard-tools
  #   tcpdump
  #   traceroute
  #   nftables
  # ];

  environment.etc = {
    "root/subnets.sh" = {
      source = pkgs.writeShellScript "subnets" ''
        export IPV4_VPN_SUBNET_STATIC_WITH_MASK="${vpnIPv4WithMask}"
        export IPV6_VPN_SUBNET_STATIC_WITH_MASK="${vpnIPv6WithMask}"
      '';
      mode = "0755";
    };

    "root/restore_internet.sh" = {
      source = pkgs.writeShellScript "restore_internet" ''
        #!/usr/bin/env bash
        sudo systemctl stop vpn-dispatcher.service
        set -euxo pipefail

        NUKE_IFACES=("tun0" "ens19" "ens20")

        echo "[+] Killing routes and rules for: ''${NUKE_IFACES[*]}"

        for IFACE in "''${NUKE_IFACES[@]}"; do
          echo "[-] Nuking interface: $IFACE"

          # Flush routes from other tables that use the interface
          for TABLE in $(ip route show table all | grep -F "$IFACE" | awk '{print $NF}' | sort -u); do
            echo "  -> Flushing routes from table $TABLE"
            ip route flush table "$TABLE" dev "$IFACE" || true
            ip -6 route flush table "$TABLE" dev "$IFACE" || true
          done

          # Delete rules that reference the interface
          ip rule | grep "$IFACE" || true
          for RULE in $(ip rule | grep "$IFACE" | awk '{print $1}'); do
            echo "  -> Deleting ip rule $RULE"
            ip rule del priority "$RULE" || true
          done

          # Detach from VRF if necessary
          if [ -e "/sys/class/net/$IFACE/master" ]; then
            echo "  -> Detaching $IFACE from VRF"
            ip link set dev "$IFACE" nomaster || true
          fi

          # Bring interface down
          ip link set dev "$IFACE" down || true
        done

        echo "[+] Flushing iptables and ip6tables for cleanup"
        iptables -F
        iptables -t nat -F
        iptables -t mangle -F
        ip6tables -F
        ip6tables -t nat -F
        ip6tables -t mangle -F


        sudo ip link set dev ens18 up
        nft delete table inet vpnblock || true
        echo "[+] Done. VRF interfaces nuked. Main interface untouched."
        ip a show dev ens18
        ip r

        echo "[+] Setting fallback DNS to 1.1.1.1 and 9.9.9.9"
        echo -e "nameserver 1.1.1.1\nnameserver 9.9.9.9" > /etc/resolv.conf

        echo "[+] Final IP state on management interface:"
        ip a show dev ens18

        echo "[+] Route table:"
        ip r

        echo "[+] Testing external connectivity:"
        ping -c 2 1.1.1.1
        curl -s https://ifconfig.me || echo "curl failed"

        echo "[✓] VRF interfaces nuked. DNS + routing restored via ens18."


      '';
      mode = "0755";
    };

    # "NetworkManager/system-connections/${management_interface}.nmconnection" = {
    #   text = ''
    #     [connection]
    #     id=${management_interface}
    #     type=ethernet
    #     interface-name=${management_interface}
    #     autoconnect=true
    #     permissions=

    #     [ipv4]
    #     method=auto
    #     route-metric=300
    #     ${if enableVRF then "" else "ignore-auto-dns=true\nnever-default=true"}

    #     [ipv6]
    #     method=auto
    #     route-metric=300
    #     ${if enableVRF then "" else "ignore-auto-dns=true\nnever-default=true"}
    #   '';
    #   mode = "0600";
    # };

    "NetworkManager/system-connections/${upstream_VPN_interface}.nmconnection" = lib.mkIf (!enableVRF) {
      text = ''
        [connection]
        id=${upstream_VPN_interface}
        type=ethernet
        interface-name=${upstream_VPN_interface}
        autoconnect=true
        permissions=

        [ipv4]
        method=auto
        route-metric=500
        ignore-auto-dns=false

        [ipv6]
        method=auto
        route-metric=100
        ignore-auto-dns=false
      '';
      mode = "0600";
    };

    "NetworkManager/system-connections/${vpnNATInterface}.nmconnection" = lib.mkIf (!enableVRF) {
      text = ''
        [connection]
        id=${vpnNATInterface}
        type=ethernet
        interface-name=${vpnNATInterface}
        autoconnect=true
        permissions=

        [ipv4]
        method=manual
        address1=${vpnIPv4WithMask}
        route-metric=1000
        ignore-auto-dns=true
        never-default=true

        [ipv6]
        method=manual
        address1=${vpnIPv6WithMask}
        route-metric=1000
        ignore-auto-dns=true
        never-default=true
      '';
      mode = "0600";
    };
  };

  networking.useNetworkd = true;

  # Disable networkd-wait-online
  systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;

  environment.systemPackages = with pkgs; [
    dnsutils
    openvpn
    wireguard-tools
    tcpdump
    traceroute
    nftables
    dhcpcd
    tmux
  ];
}
