{
  config,
  pkgs,
  lib,
  ...
}:

let
  management_interface = "ens18";
  upstream_VPN_interface = "ens19";
  vpnNATInterface = "ens20";

  vpnInterface = "tun0";
  vpnConfBasePath = "/etc/vpn";
  vpnConfPath = "${vpnConfBasePath}/${vpnInterface}.conf";
  vpnIPv4WithMask = "10.90.0.1/24";
  vpnIPv6WithMask = "fd90:dead:beef::100/64";

  # ignore this
  vrf_table_vpn = 10;
  vrf_name_vpn = "vrf-vpn";

in
{
  networking.networkmanager.enable = false;

  systemd.network.networks."10-mgmt" = {
    matchConfig.Name = management_interface;
    networkConfig.DHCP = "yes";
    routingPolicyRules = [
      {
        Priority = 100;
        From = "192.168.1.0/24"; # or just your mgmt IP /32
        Table = "main";
      }
    ];
  };

  systemd.network.netdevs."10-${vrf_name_vpn}" = {
    netdevConfig = {
      Name = vrf_name_vpn;
      Kind = "vrf";
    };
    vrfConfig.Table = vrf_table_vpn;
  };
  systemd.network.networks."10-${vrf_name_vpn}" = {
    matchConfig.Name = vrf_name_vpn;
    linkConfig.RequiredForOnline = "no";
    networkConfig = {
      DHCP = "no";
    };
  };

  systemd.network.networks."20-upstream-vpn" = {
    matchConfig.Name = upstream_VPN_interface;
    networkConfig = {
      VRF = vrf_name_vpn;
      DHCP = "yes";
    };
  };

  systemd.network.networks."30-vpn" = {
    matchConfig.Name = vpnInterface;
    networkConfig = {
      VRF = vrf_name_vpn;
      DHCP = "no";
    };
    routingPolicyRules = [
      {
        Priority = 1000;
        Table = vrf_table_vpn;
        From = vpnIPv4WithMask;
      }
    ];

  };

  systemd.slices.vrf = {
    description = "Slice for VRF-routed services";
  };

  systemd.network.networks."40-nat-iface" = {
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
  sops.secrets."vpn-configuration" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

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
        mkdir -p ${vpnConfBasePath}
        secret_path="${config.sops.secrets."vpn-configuration".path}"
        if [ -f "$secret_path" ] && [ -s "$secret_path" ]; then
        cat "$secret_path" | ${pkgs.coreutils}/bin/base64 -d > ${vpnConfPath}
        chmod 600 ${vpnConfPath}
        else
        echo "[ERROR] VPN config secret missing or empty: $secret_path" >&2
        exit 1
        fi
      '';
    };
  };

  systemd.services."nftables-vrf-mark" = {
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
    description = "Bring up VPN and reconfigure routing with VRF";
    after = [
      "systemd-networkd.service"
      "write-vpn-config.service"
    ];
    requires = [
      "systemd-networkd.service"
      "write-vpn-config.service"
    ];
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [
      iproute2
      wireguard-tools
      openvpn
      coreutils
      gawk
      nftables
      systemd
      inetutils
    ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 10;
      Slice = "vrf.slice";

      ExecStart = pkgs.writeShellScript "vpn-dispatcher-loop" ''
        set -euxo pipefail

        CONF=${vpnConfPath}
        VRF_NAME=${vrf_name_vpn}
        VRF_TABLE=${toString vrf_table_vpn}
        MGMT_IF=${management_interface}

        if grep -q "^ *${vpnInterface}:" /proc/net/dev; then
          echo "[*] ${vpnInterface} already exists, skipping setup"
        else
          echo "cant get this shit working... ffs. The main problem is that DNS will not resolve inside the VRF."
        fi
        # else
        #   echo "[*] Waiting for ${upstream_VPN_interface} to settle..."
        #   sleep 20

        #   ip route show table main    | sort -u > /run/routes.before
        #   ip -6 route show table main | sort -u > /run/routes6.before
        #   ip rule show                | sort -u > /run/rules.before
        #   ip -6 -d rule show          | sort -u > /run/rules6.before
        #   nft list ruleset > /run/nft-before.vpn
        #   cp /etc/resolv.conf /run/resolv.conf.backup || true

        #   # Block egress on MGMT_IF
        #   nft list table inet filter 2>/dev/null || nft add table inet filter
        #   nft list chain inet filter output 2>/dev/null || \
        #     nft add chain inet filter output { type filter hook output priority 0 \; }
        #   nft add rule inet filter output oifname "''${MGMT_IF}" tcp dport 22 accept comment "allow-ssh-temp-block-''${MGMT_IF}"
        #   nft add rule inet filter output oifname "''${MGMT_IF}" drop comment "temp-block-''${MGMT_IF}"


        #   if grep -qE '^\[Interface\]' "''${CONF}"; then
        #     echo "[+] WireGuard detected"
        #     timeout 2 wg-quick up "''${CONF}"
        #   elif grep -qE '^(client|dev|proto|remote)' "''${CONF}"; then
        #     echo "[+] OpenVPN detected"
        #     openvpn --config "''${CONF}" --daemon
        #     sleep 2
        #   else
        #     echo "[!] Unknown VPN config format"
        #     sleep 10
        #     continue
        #   fi

        #   ip route show table main    | sort -u > /run/routes.after
        #   ip -6 route show table main | sort -u > /run/routes6.after
        #   ip rule show                | sort -u > /run/rules.after
        #   ip -6 -d rule show          | sort -u > /run/rules6.after
        #   nft list ruleset > /run/nft-after.vpn

        #   # Enslave tun0 to VRF
        #   current_master=$(readlink "/sys/class/net/${vpnInterface}/master" || echo "")
        #   if [[ "$current_master" != *"''${VRF_NAME}"* ]]; then
        #     ip link set "${vpnInterface}" master "''${VRF_NAME}"
        #     ip link set "${vpnInterface}" up
        #   fi

        #   # Unblock egress
        #   nft -a list chain inet filter output |
        #       grep 'temp-block-' |
        #       awk '{print $NF}' | while read line
        #   do
        #     nft delete rule inet filter output handle $line
        #   done

        #   # Setup VRF-specific DNS from ens19
        #   mkdir -p "/etc/netns/''${VRF_NAME}"
        #   resolvectl dns ${upstream_VPN_interface} | \
        #     awk '{for(i=3;i<=NF;i++) print "nameserver "$i}' \
        #     > "/etc/netns/''${VRF_NAME}/resolv.conf"


        #   # Fallback if no nameserver found
        #   if ! grep -q '^nameserver' "/etc/netns/''${VRF_NAME}/resolv.conf"; then
        #     echo 'nameserver 1.1.1.1' > "/etc/netns/''${VRF_NAME}/resolv.conf"
        #   fi


        #   # Ensure management DNS always works
        #   resolvectl domain "''${MGMT_IF}" "~."

        #   # Migrate IPv4 routes
        #   grep -Fvx -f /run/routes.before /run/routes.after | while read line; do
        #     [ -n "$line" ] || continue
        #     cleaned=$(echo "$line" | sed -E 's/( proto [^ ]+| metric [0-9]+| scope [^ ]+| expires [0-9a-z]+| pref [^ ]+| nhid [0-9]+)//g')
        #     echo "[+] Moving IPv4 route to VRF table: $cleaned"
        #     ip route add $cleaned table "''${VRF_TABLE}" || true
        #     ip route del $line || true
        #   done

        #   # Migrate IPv6 routes
        #   grep -Fvx -f /run/routes6.before /run/routes6.after | while read line; do
        #     [ -n "$line" ] || continue
        #     cleaned=$(echo "$line" | sed -E 's/( proto [^ ]+| metric [0-9]+| scope [^ ]+| expires [0-9a-z]+| pref [^ ]+| nhid [0-9]+)//g')
        #     echo "[+] Moving IPv6 route to VRF table: $cleaned"
        #     ip -6 route add $cleaned table "''${VRF_TABLE}" || true
        #     ip -6 route del $line || true
        #   done

        #   # Migrate rules
        #   grep -Fvx -f /run/rules.before /run/rules.after | while IFS= read rule; do
        #     [ -n "$rule" ] || continue
        #     prio="''${rule%%:*}"
        #     rule_core=$(echo "$rule" | sed -E "s/^$prio:[[:space:]]+//" | sed -E 's/table[[:space:]]+[a-zA-Z0-9]+$//')
        #     if ! ip rule show | grep -q "priority $prio" | grep -q "lookup $VRF_TABLE"; then
        #       ip rule add $rule_core table "$VRF_TABLE" priority "$prio" || true
        #     fi
        #     ip rule del $rule_core table main priority "$prio" || true
        #   done
        # fi

        if [ ! -e /run/vpn-ready.once ]; then
          systemctl start vpn-ready.target
          touch /run/vpn-ready.once
        fi

        sleep infinity
      '';
    };
  };

  # 5. Example dependent service
  systemd.services.portforwards = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "vpn-ready.target" ];
    after = [ "vpn-ready.target" ];
    path = [
      pkgs.iptables
    ];
    serviceConfig = {
      ExecStart = pkgs.writeShellScript "portforwards" ''
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
          iptables -t nat -A PREROUTING -i ${vpnInterface} -p tcp --dport "$port" \
            -j DNAT --to-destination "$IPV4_PREFIX.$ipv4_host:$dst_port_v4"

          # IPv6 rule
          ip6tables -t nat -A PREROUTING -i ${vpnInterface} -p tcp --dport "$port" \
            -j DNAT --to-destination "[$IPV6_PREFIX:$ipv6_host_suffix]:$dst_port_v6"
        done
      '';
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  systemd.services.update_iptables_v4 = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "vpn-ready.target" ];
    after = [ "vpn-ready.target" ];
    path = [
      pkgs.networkmanager
      pkgs.iptables
      pkgs.systemd
      pkgs.util-linux
      pkgs.gawk
    ];
    serviceConfig = {
      ExecStart = pkgs.writeShellScript "update_iptables_v4" ''
        set -euo pipefail
        set -x
        # Get the current IP address of ${vpnInterface}
        source /etc/root/subnets.sh

        # IPv4_DNS_VPN=$(${pkgs.networkmanager}/bin/nmcli connection show ${vpnInterface} | grep 'ipv4.dns' | awk '{print $2}' | head -n1)
        # IPv4_DNS_VPN=$(resolvectl dns "${vpnInterface}"  | cut -d ':' -f 2 | ${pkgs.util-linux}/bin/rev | awk '{print $2; exit}' | ${pkgs.util-linux}/bin/rev)
        IPv4_DNS_VPN=$(${pkgs.systemd}/bin/resolvectl dns "${vpnInterface}" | rev | awk '{print $2; exit}' | rev)
        if [[ -z "$IPv4_DNS_VPN" || "$IPv4_DNS_VPN" == "--" ]]; then
            # If it's empty or has '--', get the first hop's IPv4 address from traceroute and assign it to IPv4_DNS_VPN
            IPv4_DNS_VPN=$(${pkgs.traceroute}/bin/traceroute --interface=${vpnInterface} -n4 -m 1 google.com | tail -n1 | awk '{print $2}')
            echo "IPV4 Tunnel IP: $IPv4_DNS_VPN"
        fi

        # logging for DNS:
        echo "IPv4_DNS_VPN: $IPv4_DNS_VPN"

        # Flush old rules for port 53 forwarding
        iptables -t nat -D PREROUTING -i ${vpnNATInterface} -p udp --dport 53 -j DNAT --to-destination $IPv4_DNS_VPN || true
        iptables -t nat -D PREROUTING -i ${vpnNATInterface} -p tcp --dport 53 -j DNAT --to-destination $IPv4_DNS_VPN || true
        # Allow forwarding to self
        iptables -I FORWARD -i ${vpnNATInterface} -o ${vpnNATInterface} -j ACCEPT
        # Portforwards DNS
        iptables -t nat -A PREROUTING -i ${vpnNATInterface} -p udp --dport 53 -j DNAT --to-destination $IPv4_DNS_VPN
        iptables -t nat -A PREROUTING -i ${vpnNATInterface} -p tcp --dport 53 -j DNAT --to-destination $IPv4_DNS_VPN
        # MASQUERADE the traffic from ${vpnIPv4WithMask} to ${vpnInterface}
        iptables -t nat -A POSTROUTING -s ${vpnIPv4WithMask} -o ${vpnInterface} -j MASQUERADE
        # MSS clamping (mtu size forcing) 
        iptables -t mangle -A FORWARD -o ${vpnInterface} -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu


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
    path = [
      pkgs.networkmanager
      pkgs.gawk
      pkgs.iproute2
      pkgs.util-linux
      pkgs.systemd
      pkgs.iptables
    ];
    serviceConfig = {
      ExecStart = pkgs.writeShellScript "update_iptables_v6" ''
        set -euo pipefail
        set -x
        # Get the current IP address of ${vpnInterface}
        source /etc/root/subnets.sh

        # IPv6_DNS_VPN=$(nmcli connection show ${vpnInterface} | grep 'ipv6.dns' | awk '{print $2}' | head -n1)
        IPv6_DNS_VPN=$(resolvectl dns "${vpnInterface}" | rev | awk '{print $1; exit}' | rev)

        IPv6_INTERFACE_NATTED_LAN=$(ip -6 a s ${vpnNATInterface} | grep 'scope global noprefixroute' | awk '{print $2}' | cut -d '/' -f 1)
        IPv6_INTERFACE_NATTED_LAN_WITH_SUBNET=$(ip -6 a s ${vpnNATInterface} | grep 'scope global noprefixroute' | awk '{print $2}')


        # Check if the DNS setting is empty or if it contains '--'
        if [[ -z "$IPv6_DNS_VPN" || "$IPv6_DNS_VPN" == "--" ]]; then
            # If it's empty or has '--', get the first hop's IPv6 address from traceroute and assign it to IPv6_DNS_VPN
            IPv6_DNS_VPN=$(${pkgs.traceroute}/bin/traceroute --interface=${vpnInterface} -n6 -m 1 google.com | tail -n1 | awk '{print $2}')
            echo "IPV6 Tunnel IP (resolved with traceroute): $IPv6_DNS_VPN"
        fi

        # logging for DNS:
        echo "IPv6_DNS_VPN: $IPv6_DNS_VPN"



        # Flush old rules for port 53 forwarding
        ip6tables -t nat -D PREROUTING -i ${vpnNATInterface} -p udp --dport 53 -j DNAT --to-destination $IPv6_DNS_VPN || true
        ip6tables -t nat -D PREROUTING -i ${vpnNATInterface} -p tcp --dport 53 -j DNAT --to-destination $IPv6_DNS_VPN || true

        # allow callbacks on the adapter itself
        ip6tables -I FORWARD -i ${vpnNATInterface} -o ${vpnNATInterface} -j ACCEPT
        # Add new rules with the current IP address
        ip6tables -t nat -A PREROUTING -i ${vpnNATInterface} -p udp --dport 53 -j DNAT --to-destination $IPv6_DNS_VPN
        ip6tables -t nat -A PREROUTING -i ${vpnNATInterface} -p tcp --dport 53 -j DNAT --to-destination $IPv6_DNS_VPN

        # DNAT any incoming UDP or TCP DNS on ${vpnNATInterface} to the real VPN DNS server
        ip6tables -t nat -A PREROUTING -i ${vpnNATInterface} -p udp --dport 53 -d $IPv6_INTERFACE_NATTED_LAN -j DNAT --to-destination "[$IPv6_DNS_VPN]:53"
        ip6tables -t nat -A PREROUTING -i ${vpnNATInterface} -p tcp --dport 53 -d $IPv6_INTERFACE_NATTED_LAN -j DNAT --to-destination "[$IPv6_DNS_VPN]:53"
        ip6tables -A FORWARD -i ${vpnNATInterface} -o ${vpnInterface} -p udp --dport 53 -d $IPv6_DNS_VPN -j ACCEPT
        ip6tables -A FORWARD -i ${vpnNATInterface} -o ${vpnInterface} -p tcp --dport 53 -d $IPv6_DNS_VPN -j ACCEPT

        # All traffic from LAN to VPN
        ip6tables -A FORWARD -i ${vpnNATInterface} -o ${vpnInterface} -s $IPv6_INTERFACE_NATTED_LAN_WITH_SUBNET -j ACCEPT

        # Return traffic
        ip6tables -A FORWARD -i ${vpnInterface} -o ${vpnNATInterface} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

        # Accept return traffic
        ip6tables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
        ip6tables -t nat -A POSTROUTING -s $IPv6_INTERFACE_NATTED_LAN_WITH_SUBNET -o ${vpnInterface} -j MASQUERADE


        ip6tables -t mangle -A FORWARD -o ${vpnInterface} -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
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
      ExecStart = "${pkgs.iproute2}/bin/ip vrf exec ${vrf_name_vpn} ${pkgs.kea}/bin/kea-dhcp4 -c /etc/kea/kea-dhcp4.conf";
      Type = "simple";
      Restart = "on-failure";
      RestartSec = 1;
      ExecStartPost = pkgs.writeShellScript "kea-dhcp4-postcheck" ''
        set -euo pipefail

        LOG="$(${pkgs.systemd}/bin/journalctl -u kea-dhcp4 -n 40)"

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
    path = [
      pkgs.radvd
      pkgs.gawk
      pkgs.sipcalc
      pkgs.iproute2
    ];

    serviceConfig = {
      ExecStart = "${pkgs.radvd}/bin/radvd -n -C /root/radvd.conf ${vpnNATInterface}";
      Restart = "on-failure";
      RestartSec = 10;
      # StartLimitIntervalSec = 0;
      StartLimitBurst = 0;
    };

    preStart = ''
      echo "Generating radvd.conf..."
      set -euo pipefail

      # Extract IPv6 address and subnet prefix for ${vpnNATInterface}
      IPV6_ADDR=$(ip -6 a s ${vpnNATInterface} | grep 'scope global' | awk '{print $2}')

      source /etc/root/subnets.sh
      IPV6_ADDR=${vpnIPv6WithMask}

      PREFIX=$(sipcalc "$IPV6_ADDR")
      PREFIX=$(sipcalc "$IPV6_ADDR" | grep 'Subnet prefix' | awk '{print $5}')
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

  environment.systemPackages = with pkgs; [
    # coreutils
    # python3
    # coreutils
    dnsutils # dig
    openvpn
    wireguard-tools
    tcpdump
    traceroute
    nftables
  ];

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
  };

  networking.useNetworkd = true;

  # Disable networkd-wait-online
  systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;
}
