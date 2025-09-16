{
  config,
  pkgs,
  lib,
  ...
}:
{
  sops.secrets."tun0-wireguard" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  systemd.services.write-tun0-conf = {
    description = "Decode tun0 WireGuard config from sops";
    wantedBy = [ "network-pre.target" ];
    before = [ "network-online.target" ]; # important: get in before any networking
    after = [ "local-fs.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "write-tun0-conf" ''
        set -euxo pipefail

        secret_path="${config.sops.secrets."tun0-wireguard".path}"

        echo "[DEBUG] Checking if secret path exists: $secret_path"
        if [ -f "$secret_path" ] && [ -s "$secret_path" ]; then
          cat "$secret_path" | ${pkgs.coreutils}/bin/base64 -d > /root/tun0.conf
          echo "[DEBUG] Written to /root/tun0.conf"
        else
          echo "[ERROR] tun0-wireguard secret is missing or empty: $secret_path" >&2
          exit 1
        fi
      '';
    };
  };

  systemd.services.import-vpn-profile = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "write-tun0-conf.service" ];
    after = [ "write-tun0-conf.service" ];

    path = [
      pkgs.networkmanager
      pkgs.util-linux
      pkgs.gawk
    ];
    serviceConfig = {
      ExecStart = "/etc/root/import-vpn-profile.sh";
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  systemd.services.portforwards = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "import-vpn-profile.service" ];
    after = [ "import-vpn-profile.service" ];
    serviceConfig = {
      ExecStart = "/etc/root/portforwards.sh";
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  systemd.services.update_iptables = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "import-vpn-profile.service" ];
    after = [ "import-vpn-profile.service" ];
    path = [ pkgs.networkmanager ];
    serviceConfig = {
      ExecStart = "/etc/root/update_iptables.sh";
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
  systemd.services.dhcpd = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "import-vpn-profile.service" ];
    after = [ "import-vpn-profile.service" ];

    serviceConfig = {
      ExecStart = "${pkgs.nix}/bin/nix shell github:NixOS/nixpkgs/32dcb45f66c0487e92db8303a798ebc548cadedc#dhcp -c dhcpd -f -cf /root/dhcpd.conf ens20";
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 10;
    };
    preStart = ''
      mkdir -p /var/db
      touch /var/db/dhcpd.leases
      /etc/root/generate-dhcpd.conf.sh
      chmod 644 /root/dhcpd.conf
    '';

  };

  systemd.services.radvd = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "import-vpn-profile.service" ];
    after = [ "import-vpn-profile.service" ];
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
      /etc/root/generate-radvd.conf.sh
      chmod 644 /root/radvd.conf
    '';
  };

  systemd.services.watchdog-networkmanager = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "import-vpn-profile.service" ];
    after = [ "import-vpn-profile.service" ];
    serviceConfig = {
      ExecStart = "/etc/root/watchdog-networkmanager.sh";
      Restart = "always";
    };
  };

  environment.systemPackages = with pkgs; [
    coreutils
    python3
  ];

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };
  boot.kernelModules = [
    "ip6table_nat"
  ];

  networking.networkmanager.enable = true;
  networking.networkmanager.unmanaged = [ ];

  # 3) Copy everything from /etc/root into /root at activation time
  system.activationScripts.copyToRoot = {
    text = ''
      for f in /etc/root/*; do
        install -D -m0755 "$f" "/root/$(basename $f)"
      done
    '';
    deps = [ "etc" ];
  };

  # services.cron.enable = true;

  # environment.etc = {
  #   "NetworkManager/system-connections/ens18.nmconnection" = {
  #     text = ''
  #       [connection]
  #       id=ens18
  #       type=ethernet
  #       interface-name=ens18
  #       autoconnect=true
  #       permissions=

  #       [ipv4]
  #       method=auto
  #       route-metric=300
  #       ignore-auto-dns=true
  #       never-default=true

  #       [ipv6]
  #       method=auto
  #       route-metric=300
  #       ignore-auto-dns=true
  #       never-default=true
  #     '';
  #     mode = "0600";
  #   };

  #   "NetworkManager/system-connections/ens19.nmconnection" = {
  #     text = ''
  #       [connection]
  #       id=ens19
  #       type=ethernet
  #       interface-name=ens19
  #       autoconnect=true
  #       permissions=

  #       [ipv4]
  #       method=auto
  #       route-metric=100
  #       ignore-auto-dns=false

  #       [ipv6]
  #       method=auto
  #       route-metric=100
  #       ignore-auto-dns=false
  #     '';
  #     mode = "0600";
  #   };

  #   "NetworkManager/system-connections/ens20.nmconnection" = {
  #     text = ''
  #       [connection]
  #       id=ens20
  #       type=ethernet
  #       interface-name=ens20
  #       autoconnect=true
  #       permissions=

  #       [ipv4]
  #       method=manual
  #       address1=10.90.0.1/24
  #       route-metric=250
  #       ignore-auto-dns=true

  #       [ipv6]
  #       method=manual
  #       address1=fd90:dead:beef::100/64
  #       route-metric=250
  #       ignore-auto-dns=true
  #     '';
  #     mode = "0600";
  #   };
  # };
  systemd.services."generate-nmconnections" = {
    description = "Generate NetworkManager .nmconnection profiles at boot";
    wantedBy = [ "network-pre.target" ];
    before = [ "NetworkManager.service" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "generate-nmconnections" ''
                mkdir -p /etc/NetworkManager/system-connections
                chmod 700 /etc/NetworkManager/system-connections

                echo "[connection]
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
        never-default=true" > /etc/NetworkManager/system-connections/ens18.nmconnection

                echo "[connection]
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
        ignore-auto-dns=false" > /etc/NetworkManager/system-connections/ens19.nmconnection

                echo "[connection]
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
        ignore-auto-dns=true" > /etc/NetworkManager/system-connections/ens20.nmconnection

                chmod 600 /etc/NetworkManager/system-connections/*.nmconnection
      '';
    };
  };

  environment.etc = {
    "root/pre-setup-script.sh" = {
      source = pkgs.writeShellScript "pre-setup-script" ''
        set -euo pipefail
        ${pkgs.networkmanager}/bin/nmcli conn | grep -v 'ens18\|lo \|NAME ' | ${pkgs.util-linux}/bin/rev | ${pkgs.gawk}/bin/awk '{print $3}' | ${pkgs.util-linux}/bin/rev | xargs -I {} ${pkgs.networkmanager}/bin/nmcli con del {}
        ${pkgs.networkmanager}/bin/nmcli con add con-name ens19 type ethernet ifname ens19 ipv4.method auto
      '';
      mode = "0755";
    };

    "root/subnets.sh" = {
      source = pkgs.writeShellScript "subnets" ''
        export IPV4_VPN_SUBNET_STATIC_WITH_MASK="10.90.0.1/24"
        export IPV6_VPN_SUBNET_STATIC_WITH_MASK="fd90:dead:beef::100/64"
      '';
      mode = "0755";
    };

    "root/generate-dhcpd.conf.sh" = {
      source = pkgs.writeShellScript "generate-dhcpd.conf.sh" ''
        set -euo pipefail
        set -x
        mkdir /etc/dhcp/ 2>/dev/null || true
        IPV4_ADDR=$(${pkgs.iproute2}/bin/ip -4 a s ens20 | grep 'scope global' | ${pkgs.gawk}/bin/awk '{print $2}')
        source /etc/root/subnets.sh
        IPV4_ADDR=$IPV4_VPN_SUBNET_STATIC_WITH_MASK
        ${pkgs.sipcalc}/bin/sipcalc "$IPV4_ADDR"
        IPV4_PREFIX=$(${pkgs.sipcalc}/bin/sipcalc "$IPV4_ADDR" | grep -i 'network range' | ${pkgs.util-linux}/bin/rev | ${pkgs.gawk}/bin/awk '{print $3}' | ${pkgs.util-linux}/bin/rev )
        IPV4_MASK=$(${pkgs.sipcalc}/bin/sipcalc "$IPV4_ADDR" | grep -i 'network mask' | grep 255 | ${pkgs.gawk}/bin/awk -F'-' '{print $2}')
        IPV4_ADDR_GATEWAY=$(echo $IPV4_ADDR | sed 's/\/.*//g')
        IPV4_USABLE_RANGE=$(${pkgs.sipcalc}/bin/sipcalc "$IPV4_ADDR" | grep -i 'usable range' | ${pkgs.util-linux}/bin/rev | ${pkgs.gawk}/bin/awk -F'-' '{print $1, $2}' | ${pkgs.util-linux}/bin/rev | sed 's/.1 /.10/g') # Usable range
        # echo $IPV4_ADDR
        # echo $IPV4_PREFIX
        # echo $IPV4_MASK
        # echo $IPV4_ADDR_GATEWAY
        # echo $IPV4_USABLE_RANGE
        echo "default-lease-time 600;
        max-lease-time 600;
        subnet $IPV4_PREFIX netmask $IPV4_MASK {
          range $IPV4_USABLE_RANGE;
          option routers $IPV4_ADDR_GATEWAY; # Default gateway
          option subnet-mask $IPV4_MASK;          # Net mask 
          option domain-name-servers $IPV4_ADDR_GATEWAY; # dns host, gateway our case
        }" | tee /root/dhcpd.conf
      '';
      mode = "0755";
    };

    # setup-generic.sh
    "root/setup-generic.sh" = {
      source = pkgs.writeShellScript "setup-generic" ''
        set -euo pipefail
        source /etc/root/subnets.sh
        ${pkgs.networkmanager}/bin/nmcli connection up tun0
        ${pkgs.networkmanager}/bin/nmcli connection down ens20
        ${pkgs.networkmanager}/bin/nmcli connection up ens20
        ${pkgs.networkmanager}/bin/nmcli connection modify "tun0" connection.autoconnect yes
        ${pkgs.networkmanager}/bin/nmcli connection add type ethernet ifname ens20 con-name ens20 ipv4.addresses "$IPV4_VPN_SUBNET_STATIC_WITH_MASK" ipv4.method manual
        ${pkgs.networkmanager}/bin/nmcli connection modify ens20 ipv6.addresses "$IPV6_VPN_SUBNET_STATIC_WITH_MASK"
        ${pkgs.networkmanager}/bin/nmcli connection modify ens20 ipv6.method manual
        ${pkgs.networkmanager}/bin/nmcli connection modify ens20 ipv6.dns "$IPV6_VPN_SUBNET_STATIC_WITH_MASK"
        /etc/root/generate-dhcpd.conf.sh
        /etc/root/generate-radvd.conf.sh
        ${pkgs.networkmanager}/bin/nmcli connection up tun0
        ${pkgs.networkmanager}/bin/nmcli connection up tun0
        ${pkgs.networkmanager}/bin/nmcli connection up tun0
        ${pkgs.networkmanager}/bin/nmcli connection up tun0

        #reboot
      '';
      mode = "0755";
    };

    # generate-radvd.conf.sh
    "root/generate-radvd.conf.sh" = {
      source = pkgs.writeShellScript "generate-radvd.conf.sh" ''
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
      '';
      mode = "0755";
    };

    "root/import-vpn-profile.sh" = {
      source = pkgs.writeShellScript "import-vpn-profile.sh" ''
        set -euo pipefail
        set -x
        # these settings make nmcli tun0 a low priority interface (we don't need to tunnel traffic through it, except for the ens20 lan side):
        until ${pkgs.networkmanager}/bin/nmcli networking connectivity check &>/dev/null; do
          sleep 1
        done

        ${pkgs.networkmanager}/bin/nmcli conn | grep 'tun0' | ${pkgs.util-linux}/bin/rev | ${pkgs.gawk}/bin/awk '{print $3}' | ${pkgs.util-linux}/bin/rev | xargs -I {} ${pkgs.networkmanager}/bin/nmcli con del {} || true
        ${pkgs.networkmanager}/bin/nmcli connection import type wireguard file /root/tun0.conf
        ${pkgs.networkmanager}/bin/nmcli connection modify tun0 ipv4.route-metric 1000
        ${pkgs.networkmanager}/bin/nmcli connection modify tun0 ipv6.route-metric 1000
      '';
      mode = "0755";
    };

    "root/update_iptables.sh" = {
      source = pkgs.writeShellScript "update_iptables.sh" ''
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

      '';
      mode = "0755";
    };

    # portforwards.sh
    "root/portforwards.sh" = {
      source = pkgs.writeShellScript "portforwards.sh" ''
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
      mode = "0755";
    };

    # watchdog-networkmanager.sh
    "root/watchdog-networkmanager.sh" = {
      source = pkgs.writeShellScript "watchdog-networkmanager.sh" ''
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
            echo "[$(date)] No RX activity on $interface. Probing with ping to confirm..."

            if ! ${pkgs.iputils}/bin/ping -c1 -I "$interface" -W 2 8.8.8.8 >/dev/null 2>&1; then
              echo "[$(date)] Ping failed on $interface. Restarting NetworkManager..."
              ${pkgs.systemd}/bin/systemctl restart NetworkManager
              sleep 3
            else
              echo "[$(date)] Ping succeeded. Likely idle traffic on $interface."
            fi
          else
            echo "[$(date)] RX bytes changed: $RX_BEFORE → $RX_AFTER. Interface OK."
          fi
        done
      '';
      mode = "0755";
    };

  };
  networking.useNetworkd = true;

  # Disable networkd-wait-online
  systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;
}
