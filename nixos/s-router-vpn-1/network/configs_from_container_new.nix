{
  config,
  lib,
  pkgs,
  ...
}:
{
  # 1) Ensure cp/install/chmod are in $PATH
  environment.systemPackages = with pkgs; [
    coreutils
    python3
  ];

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };
  boot.kernelModules = [
    "nf_nat_ipv6"
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

  environment.etc = {
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

    "NetworkManager/system-connections/ens20.nmconnection" = {
      text = ''
        [connection]
        id=ens20
        type=ethernet
        interface-name=ens20
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

    "NetworkManager/system-connections/ens21.nmconnection" = {
      text = ''
        [connection]
        id=ens21
        type=ethernet
        interface-name=ens21
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

  services.cron.systemCronJobs = [
    #   # "0 * * * * root /path/to/your/script.sh"
    #   # "*/5 * * * * root /root/update_iptables.sh"
    #   # "@reboot root bash -c \"sleep 1; touch /var/run/dhcpd.pid; /usr/sbin/dhcpd -4 -q -cf /etc/dhcp/dhcpd.conf ens21\""
    #   # "@reboot root systemctl start isc-dhcp-server"
    #   # "@reboot root /root/watchdog-networkmanager.sh > /tmp/watchdog-networkmanager.sh.out"
    #   # "@reboot root bash -c \"sleep 10; /root/portforwards.sh ; /root/update_iptables.sh\""
    "@reboot root bash -c \"sleep 10; /root/import-vpn-profile.sh\""
  ];

  systemd.services.portforwards = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = "/root/portforwards.sh";
      Restart = "on-failure";
    };
  };

  systemd.services.import-vpn-profile = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.networkmanager ];
    serviceConfig = {
      ExecStart = "/root/import-vpn-profile.sh";
      Restart = "on-failure";
    };
  };

  # systemd.timers.update_iptables = {
  #   wantedBy = [ "timers.target" ];
  #   timerConfig = {
  #     OnBootSec = "2min";
  #     OnUnitActiveSec = "5min";
  #     Persistent = true;
  #   };
  # };

  systemd.services.update_iptables = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.networkmanager ];
    serviceConfig = {
      ExecStart = "/root/update_iptables.sh";
      Restart = "on-failure";
    };
  };
  systemd.services.watchdog-networkmanager = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "/root/watchdog-networkmanager.sh";
      Restart = "always";
    };
  };

  environment.etc = {
    # calculate-prefix.py → /etc/root/calculate-prefix.py
    "root/calculate-prefix.py" = {
      source = pkgs.writeTextFile {
        name = "calculate-prefix.py";
        text = ''
          #!${pkgs.python3}/bin/python3
          import argparse
          import ipaddress

          def expand_ipv6_address(address):
              """Expand an IPv6 address to its full notation."""
              return ipaddress.ip_address(address.split('/')[0]).exploded

          def extract_network_prefix(address, length):
              """Extract the network prefix based on the prefix length."""
              blocks = address.split(':')
              num_full_blocks = length // 16
              relevant_blocks = blocks[:num_full_blocks]
              # Ensure the output is formatted to show the complete segment with trailing zeros
              return ':'.join(relevant_blocks) + (':0' * (4 - num_full_blocks)) + ':'

          def main():
              # Create argument parser
              parser = argparse.ArgumentParser(description='Process an IPv6 address in the format address/prefix_length.')
              parser.add_argument('ipv6_cidr', type=str, help='The IPv6 CIDR notation to be processed')

              # Parse arguments
              args = parser.parse_args()

              # Split the address and prefix length
              address, length = args.ipv6_cidr.split('/')
              length = int(length)

              # Process the IPv6 address
              expanded_ipv6 = expand_ipv6_address(args.ipv6_cidr)
              network_prefix = extract_network_prefix(expanded_ipv6, length)

              # Output results
              #print("Expanded IPv6 Address:", expanded_ipv6)
              print(network_prefix)

          if __name__ == "__main__":
              main()
        '';
      };
      mode = "0755";
    };

    # pre-setup-script.sh → /etc/root/pre-setup-script.sh
    "root/pre-setup-script.sh" = {
      source = pkgs.writeShellScript "pre-setup-script" ''
        #!/usr/bin/env bash
        ${pkgs.networkmanager}/bin/nmcli conn | grep -v 'ens18\|lo \|NAME ' | rev | awk '{print $3}' | rev | xargs -I {} ${pkgs.networkmanager}/bin/nmcli con del {}
        ${pkgs.networkmanager}/bin/nmcli con add con-name ens20 type ethernet ifname ens20 ipv4.method auto
      '';
      mode = "0755";
    };

    # subnets.sh → /etc/root/subnets.sh
    "root/subnets.sh" = {
      source = pkgs.writeShellScript "subnets" ''
        #!/usr/bin/env bash
        export IPV4_VPN_SUBNET_STATIC_WITH_MASK="10.90.0.1/24"
        export IPV6_VPN_SUBNET_STATIC_WITH_MASK="fd90:dead:beef::100/64"
      '';
      mode = "0755";
    };

    # generate-dhcpd.conf.sh → /etc/root/generate-dhcpd.conf.sh
    "root/generate-dhcpd.conf.sh" = {
      source = pkgs.writeShellScript "generate-dhcpd.conf.sh" ''
        #!/usr/bin/env bash
        mkdir /etc/dhcp/ 2>/dev/null || true
        IPV4_ADDR=$(${pkgs.iproute2}/bin/ip -4 a s ens21 | grep 'scope global' | awk '{print $2}')
        source /root/subnets.sh
        IPV4_ADDR=$IPV4_VPN_SUBNET_STATIC_WITH_MASK
        sipcalc "$IPV4_ADDR"
        IPV4_PREFIX=$(sipcalc "$IPV4_ADDR" | grep -i 'network range' | rev | awk '{print $3}' | rev )
        IPV4_MASK=$(sipcalc "$IPV4_ADDR" | grep -i 'network mask' | grep 255 | awk -F'-' '{print $2}')
        IPV4_ADDR_GATEWAY=$(echo $IPV4_ADDR | sed 's/\/.*//g')
        IPV4_USABLE_RANGE=$(sipcalc "$IPV4_ADDR" | grep -i 'usable range' | rev | awk -F'-' '{print $1, $2}' | rev | sed 's/.1 /.10/g') # Usable range
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
        }" | tee /etc/dhcp/dhcpd.conf
      '';
      mode = "0755";
    };

    # setup-generic.sh
    "root/setup-generic.sh" = {
      source = pkgs.writeShellScript "setup-generic" ''
        source /root/subnets.sh
        ${pkgs.networkmanager}/bin/nmcli connection up tun0
        ${pkgs.networkmanager}/bin/nmcli connection down ens21
        ${pkgs.networkmanager}/bin/nmcli connection up ens21
        ${pkgs.networkmanager}/bin/nmcli connection modify "tun0" connection.autoconnect yes
        ${pkgs.networkmanager}/bin/nmcli connection add type ethernet ifname ens21 con-name ens21 ipv4.addresses "$IPV4_VPN_SUBNET_STATIC_WITH_MASK" ipv4.method manual
        ${pkgs.networkmanager}/bin/nmcli connection modify ens21 ipv6.addresses "$IPV6_VPN_SUBNET_STATIC_WITH_MASK"
        ${pkgs.networkmanager}/bin/nmcli connection modify ens21 ipv6.method manual
        ${pkgs.networkmanager}/bin/nmcli connection modify ens21 ipv6.dns "$IPV6_VPN_SUBNET_STATIC_WITH_MASK"
        /root/generate-dhcpd.conf.sh
        /root/generate-radvd.conf.sh
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
        #!/usr/bin/env bash

        # Extract IPv6 address and subnet prefix for ens21
        IPV6_ADDR=$(${pkgs.iproute2}/bin/ip -6 a s ens21 | grep 'scope global' | awk '{print $2}')

        source /root/subnets.sh
        IPV6_ADDR=$IPV6_VPN_SUBNET_STATIC_WITH_MASK

        PREFIX=$(sipcalc "$IPV6_ADDR") # | grep 'Subnet prefix' | awk '{print $3}')
        PREFIX=$(sipcalc "$IPV6_ADDR" | grep 'Subnet prefix' | awk '{print $5}')
        IPV6_ADDR_WITHOUT_MASK=$(echo $IPV6_ADDR | sed 's/\/.*//g')
        echo -n 'interface ens21 {
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
        };' | tee /etc/radvd.conf
      '';
      mode = "0755";
    };

    # setup-openvpn.sh
    "root/setup-openvpn.sh" = {
      source = pkgs.writeShellScript "setup-openvpn.sh" ''
        #!/usr/bin/env bash
        source /root/subnets.sh
        /root/pre-setup-script.sh
        ${pkgs.networkmanager}/bin/nmcli connection import type openvpn file /root/tun0.ovpn
        /usr/bin/env bash /root/setup-generic.sh
      '';
      mode = "0755";
    };

    "root/import-vpn-profile.sh" = {
      source = pkgs.writeShellScript "import-vpn-profile.sh" ''
        # these settings make nmcli tun0 a low priority interface (we don't need to tunnel traffic through it, except for the ens21 lan side):
        ${pkgs.networkmanager}/bin/nmcli conn | grep 'tun0' | ${pkgs.util-linux}/bin/rev | ${pkgs.gawk}/bin/awk '{print $3}' | ${pkgs.util-linux}/bin/rev | xargs -I {} ${pkgs.networkmanager}/bin/nmcli con del {}
        ${pkgs.networkmanager}/bin/nmcli connection import type wireguard file /root/tun0.conf
        ${pkgs.networkmanager}/bin/nmcli connection modify tun0 ipv4.route-metric 1000
        ${pkgs.networkmanager}/bin/nmcli connection modify tun0 ipv6.route-metric 1000
      '';
      mode = "0755";
    };

    # update_iptables.sh
    "root/update_iptables.sh" = {
      source = pkgs.writeShellScript "update_iptables.sh" ''
        #!/bin/bash


        # Get the current IP address of tun0
        #TUN_IP_v4=$(${pkgs.iproute2}/bin/ip addr show tun0 | grep 'inet ' | ${pkgs.gawk}/bin/awk '{print $2}' | cut -d/ -f1)
        TUN_IP_v4=$(${pkgs.networkmanager}/bin/nmcli connection show tun0 | grep 'ipv4.dns' | ${pkgs.gawk}/bin/awk '{print $2}' | head -n1)
        TUN_IP_v6=$(${pkgs.networkmanager}/bin/nmcli connection show tun0 | grep 'ipv6.dns' | ${pkgs.gawk}/bin/awk '{print $2}' | head -n1)


        # traceroute --interface=tun0 -n4 -m 1 google.com | tail -n1 | awk '{print $2}'
        if [[ -z "$TUN_IP_v4" || "$TUN_IP_v4" == "--" ]]; then
            # If it's empty or has '--', get the first hop's IPv4 address from traceroute and assign it to TUN_IP_v4
            TUN_IP_v4=$(${pkgs.traceroute}/bin/traceroute --interface=tun0 -n4 -m 1 google.com | tail -n1 | ${pkgs.gawk}/bin/awk '{print $2}')
            echo "IPV4 Tunnel IP: $TUN_IP_v4"
        fi

        # Check if the DNS setting is empty or if it contains '--'
        if [[ -z "$TUN_IP_v6" || "$TUN_IP_v6" == "--" ]]; then
            # If it's empty or has '--', get the first hop's IPv6 address from traceroute and assign it to TUN_IP_v6
            TUN_IP_v6=$(${pkgs.traceroute}/bin/traceroute --interface=tun0 -n6 -m 1 google.com | tail -n1 | ${pkgs.gawk}/bin/awk '{print $2}')
            echo "IPV6 Tunnel IP: $TUN_IP_v6"
        fi
        #TUN_IP_v6=$(${pkgs.traceroute}/bin/traceroute --interface=tun0 -n6 -m 1 google.com | tail -n1 | ${pkgs.gawk}/bin/awk '{print $2}')

        echo $TUN_IP_v4 | tee "/tmp/dns-ipv4-from-$(basename "$0").txt"
        echo $TUN_IP_v6 | tee "/tmp/dns-ipv6-from-$(basename "$0").txt"
        # Flush old rules for port 53 forwarding
        ${pkgs.iptables}/bin/iptables -t nat -D PREROUTING -i ens21 -p udp --dport 53 -j DNAT --to-destination $TUN_IP_v4
        ${pkgs.iptables}/bin/iptables -t nat -D PREROUTING -i ens21 -p tcp --dport 53 -j DNAT --to-destination $TUN_IP_v4

        # Allow callbacks in the local network (added 2024)
        ${pkgs.iptables}/bin/iptables -I FORWARD -i ens21 -o ens21 -j ACCEPT
        ${pkgs.iptables}/bin/ip6tables -I FORWARD -i ens21 -o ens21 -j ACCEPT

        # Add new rules with the current IP address
        ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -i ens21 -p udp --dport 53 -j DNAT --to-destination $TUN_IP_v4
        ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -i ens21 -p tcp --dport 53 -j DNAT --to-destination $TUN_IP_v4


        # ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.90.0.0/24 -o tun0 -p udp --dport 53 -j MASQUERADE
        # ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.90.0.0/24 -o tun0 -p tcp --dport 53 -j MASQUERADE

        # Masquerade *all* IPv4 traffic from ens21 out tun0
        # ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.90.0.0/24 -o tun0 -j MASQUERADE

        # Masquerade *all* IPv6 traffic from ens21 out tun0
        # ${pkgs.iptables}/bin/ip6tables -t nat -A POSTROUTING -s fd90:dead:beef::/64 -o tun0 -j MASQUERADE

        # !!!! THIS IS WHERE IT GOES WRONG !!!!
        # DNS will not resolved with these rules (testing 2025-09-13)
        # ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -o tun0 -d $TUN_IP_v4 -p udp --dport 53 -j MASQUERADE
        # ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -o tun0 -d $TUN_IP_v4 -p tcp --dport 53 -j MASQUERADE

        # !!!! THIS IS WHERE IT GOES WRONG !!!!
        # # portforward everything (doesn't work, at reboot, the vpn is not resolved......):
        # ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
        # ${pkgs.iptables}/bin/ip6tables -t nat -A POSTROUTING -o tun0 -j MASQUERADE

        ## Only MASQUERADE DNS traffic coming from ens21
        # iptables v1.8.11 (nf_tables): Can't use --in-interface with POSTROUTING
        # Try `iptables -h' or 'iptables --help' for more information.
        # ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -i ens21 -o tun0 -d $TUN_IP_v4 -p udp --dport 53 -j MASQUERADE
        # ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -i ens21 -o tun0 -d $TUN_IP_v4 -p tcp --dport 53 -j MASQUERADE

        ## do the same for ipv6
        # ip6tables v1.8.11 (nf_tables): Can't use --in-interface with POSTROUTING
        # Try `ip6tables -h' or 'ip6tables --help' for more information.
        # ${pkgs.iptables}/bin/ip6tables -t nat -A POSTROUTING -i ens21 -o tun0 -d $TUN_IP_v6 -p udp --dport 53 -j MASQUERADE
        # ${pkgs.iptables}/bin/ip6tables -t nat -A POSTROUTING -i ens21 -o tun0 -d $TUN_IP_v6 -p tcp --dport 53 -j MASQUERADE

        ##  Optional full masquerading for traffic coming *from* ens21 and going *out* tun0
        # iptables v1.8.11 (nf_tables): Can't use --in-interface with POSTROUTING
        # Try `iptables -h' or 'iptables --help' for more information.
        # so doesn't work:
        # ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -i ens21 -o tun0 -j MASQUERADE
        # ${pkgs.iptables}/bin/ip6tables -t nat -A POSTROUTING -i ens21 -o tun0 -j MASQUERADE

        source /root/subnets.sh
        ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s $IPV4_VPN_SUBNET_STATIC_WITH_MASK -o tun0 -j MASQUERADE

        # Flush old rules for port 53 forwarding
        ${pkgs.iptables}/bin/ip6tables -t nat -D PREROUTING -i ens21 -p udp --dport 53 -j DNAT --to-destination $TUN_IP_v6 2>/dev/null
        ${pkgs.iptables}/bin/ip6tables -t nat -D PREROUTING -i ens21 -p tcp --dport 53 -j DNAT --to-destination $TUN_IP_v6 2>/dev/null

        # Add new rules with the current IP address
        ${pkgs.iptables}/bin/ip6tables -t nat -A PREROUTING -i ens21 -p udp --dport 53 -j DNAT --to-destination $TUN_IP_v6
        ${pkgs.iptables}/bin/ip6tables -t nat -A PREROUTING -i ens21 -p tcp --dport 53 -j DNAT --to-destination $TUN_IP_v6
        # old shit that didn't work:
        # ${pkgs.iptables}/bin/ip6tables -t nat -A POSTROUTING -s $IPV6_VPN_SUBNET_STATIC_WITH_MASK -o tun0 -j MASQUERADE


        IPv6_INTERFACE_NATTED_LAN=$(${pkgs.iproute2}/bin/ip -6 a s ens21 | grep 'scope global noprefixroute' | ${pkgs.gawk}/bin/awk '{print $2}' | cut -d '/' -f 1)
        IPv6_INTERFACE_NATTED_LAN_WITH_SUBNET=$(${pkgs.iproute2}/bin/ip -6 a s ens21 | grep 'scope global noprefixroute' | ${pkgs.gawk}/bin/awk '{print $2}')
        IPv6_DNS_VPN=$(${pkgs.networkmanager}/bin/nmcli connection show tun0 | grep 'ipv6.dns' | ${pkgs.gawk}/bin/awk '{print $2}' | head -n1)
        # DNAT any incoming UDP or TCP DNS on ens21 to the real VPN DNS server
        ${pkgs.iptables}/bin/ip6tables -t nat -A PREROUTING -i ens21 -p udp --dport 53 -d $IPv6_INTERFACE_NATTED_LAN -j DNAT --to-destination "[$IPv6_DNS_VPN]:53"
        ${pkgs.iptables}/bin/ip6tables -t nat -A PREROUTING -i ens21 -p tcp --dport 53 -d $IPv6_INTERFACE_NATTED_LAN -j DNAT --to-destination "[$IPv6_DNS_VPN]:53"

        # Allow the traffic to be forwarded from LAN → VPN
        ${pkgs.iptables}/bin/ip6tables -A FORWARD -i ens21 -o tun0 -p udp --dport 53 -d $IPv6_DNS_VPN -j ACCEPT
        ${pkgs.iptables}/bin/ip6tables -A FORWARD -i ens21 -o tun0 -p tcp --dport 53 -d $IPv6_DNS_VPN -j ACCEPT

        # All traffic from LAN to VPN
        ${pkgs.iptables}/bin/ip6tables -A FORWARD -i ens21 -o tun0 -s $IPv6_INTERFACE_NATTED_LAN_WITH_SUBNET -j ACCEPT

        # Return traffic
        ${pkgs.iptables}/bin/ip6tables -A FORWARD -i tun0 -o ens21 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

        # Accept return traffic
        ${pkgs.iptables}/bin/ip6tables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

        ${pkgs.iptables}/bin/ip6tables -t nat -A POSTROUTING -s $IPv6_INTERFACE_NATTED_LAN_WITH_SUBNET -o tun0 -j MASQUERADE

      '';
      mode = "0755";
    };

    # portforwards.sh
    "root/portforwards.sh" = {
      source = pkgs.writeShellScript "portforwards.sh" ''
        #!/bin/bash
        #update this shit!
        IPV6_ADDR=$(${pkgs.iproute2}/bin/ip -6 a s ens21 | grep 'scope global' | ${pkgs.gawk}/bin/awk '{print $2}')
        IPV6_PREFIX=$(/root/calculate-prefix.py $(echo $IPV6_ADDR) | sed 's/0000://g')
        # ipv6:
        ${pkgs.iptables}/bin/ip6tables -t nat -A PREROUTING -i tun0 -p tcp --dport 21612 -j DNAT --to-destination [$IPV6_PREFIX:a28f:aa25:f510:bdcb]:22
        ${pkgs.iptables}/bin/ip6tables -t nat -A PREROUTING -i tun0 -p tcp --dport 21613 -j DNAT --to-destination [$IPV6_PREFIX:be24:11ff:fe3d:474d]:443
        ${pkgs.iptables}/bin/ip6tables -t nat -A PREROUTING -i tun0 -p tcp --dport 21614 -j DNAT --to-destination [$IPV6_PREFIX:a133:c085:eeab:f2c1]:21614
        # ipv4:
        ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -i tun0 -p tcp --dport 21612 -j DNAT --to-destination 10.30.0.109:22
        ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -i tun0 -p tcp --dport 21613 -j DNAT --to-destination 10.30.0.167:443
        ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -i tun0 -p tcp --dport 21614 -j DNAT --to-destination 10.30.0.163:21614
      '';
      mode = "0755";
    };

    # setup-wireguard.sh
    "root/setup-wireguard.sh" = {
      source = pkgs.writeShellScript "setup-wireguard.sh" ''
        #!/usr/bin/env bash
        source /root/subnets.sh
        /root/pre-setup-script.sh
        ${pkgs.networkmanager}/bin/nmcli connection import type wireguard file /root/tun0.conf 
        /usr/bin/env bash /root/setup-generic.sh
      '';
      mode = "0755";
    };

    # watchdog-networkmanager.sh
    "root/watchdog-networkmanager.sh" = {
      source = pkgs.writeShellScript "watchdog-networkmanager.sh" ''
        #!/bin/bash

        # Variables
        destination="1.1.1.1"  # IP to ping
        interface="tun0"        # Network interface
        ping_count=10           # Number of pings to send each time
        drop_threshold=50       # Packet drop percentage threshold

        # Continuous check
        while true; do
          # Run the ping with a 1-second timeout and capture output
          ping_output=$(${pkgs.iputils}/bin/ping -I $interface -c $ping_count -W 1 $destination 2>&1)

          # Check for "Network is unreachable" or packet loss
          packet_loss=$(echo "$ping_output" | grep -oP '\d+(?=% packet loss)')

          if echo "$ping_output" | grep -q "Network is unreachable" || [ -z "$packet_loss" ] || [ "$packet_loss" -gt "$drop_threshold" ]; then
            echo "Network is unreachable or packet loss exceeds $drop_threshold%. Restarting Network Manager."
            ${pkgs.iproute2}/bin/ip a flush ens20
            ${pkgs.systemd}/bin/systemctl restart NetworkManager
            sleep 3
            # /root/portforwards.sh
          elif [ "$packet_loss" -eq 0 ]; then
            echo "Packet loss is 0%, network is functioning correctly. No restart needed."
          else
            echo "Packet loss is $packet_loss%, below threshold of $drop_threshold%. No action needed."
          fi

          # Wait for the next check
          sleep 30
        done
      '';
      mode = "0755";
    };
  };
  networking.useNetworkd = true;

  systemd.services.dhcpd = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    # path = [ pkgs.isc-dhcp-server ];

    serviceConfig = {
      ExecStart = "${pkgs.nix}/bin/nix shell github:NixOS/nixpkgs/32dcb45f66c0487e92db8303a798ebc548cadedc#dhcp -c dhcpd -f -cf /etc/dhcp/dhcpd.conf ens21";
      Restart = "on-failure";
    };
    preStart = ''
      mkdir -p /var/db
      touch /var/db/dhcpd.leases
      # /root/generate-dhcpd.conf.sh
      chmod 644 /etc/dhcp/dhcpd.conf
    '';

  };

  systemd.services.radvd = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = [ pkgs.radvd ];

    serviceConfig = {
      ExecStart = "${pkgs.radvd}/bin/radvd -n -C /etc/radvd.conf ens21";
      Restart = "on-failure";
    };

    # preStart = ''
    #   echo "Generating radvd.conf..."
    #   /etc/gen-radvd.sh > /etc/radvd.conf
    #   chmod 644 /etc/radvd.conf
    # '';
  };

  # Disable networkd-wait-online
  systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;
}
