{ config, pkgs, ... }:
{
  # Enable IP forwarding for both IPv4 and IPv6.
  # networking.enableIPForwarding = true;

  # Make sure IPv6 is enabled for the firewall.
  # networking.firewall.ipv6.enable = true;
  environment.systemPackages = with pkgs; [
    nftables
  ];

  networking.firewall = {
    enable = false;

    extraCommands = ''
      # --- IPv4 Rules ---
      # Allow traffic loopback on eth1.
      iptables -A FORWARD -i eth1 -o eth1 -j ACCEPT

      # Forward traffic between eth1 and tun0.
      iptables -A FORWARD -i eth1 -o tun0 -j ACCEPT
      iptables -A FORWARD -i tun0 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT

      # NAT for IPv4.
      iptables -t nat -A PREROUTING -i tun0 -p tcp --dport 21613 -j DNAT --to-destination 10.13.37.11:22
      iptables -t nat -A PREROUTING -i tun0 -p udp --dport 21613 -j DNAT --to-destination 10.13.37.11:51820
      iptables -t nat -A PREROUTING -i eth1 -p udp --dport 53 -j DNAT --to-destination 10.128.0.1
      iptables -t nat -A PREROUTING -i eth1 -p tcp --dport 53 -j DNAT --to-destination 10.128.0.1
      iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE

      # --- IPv6 Rules ---
      # Allow IPv6 traffic loopback on eth1.
      ip6tables -A FORWARD -i eth1 -o eth1 -j ACCEPT

      # Forward IPv6 traffic between eth1 and tun0.
      ip6tables -A FORWARD -i eth1 -o tun0 -j ACCEPT
      ip6tables -A FORWARD -i tun0 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT

      # NAT for IPv6.
      ip6tables -t nat -A PREROUTING -i tun0 -p tcp --dport 21613 -j DNAT --to-destination [fd03:1337::101]:22
      ip6tables -t nat -A PREROUTING -i tun0 -p udp --dport 21613 -j DNAT --to-destination [fd03:1337::101]:51820
      ip6tables -t nat -A PREROUTING -i eth1 -p udp --dport 53 -j DNAT --to-destination fd7d:76ee:e68f:a993::1
      ip6tables -t nat -A PREROUTING -i eth1 -p tcp --dport 53 -j DNAT --to-destination fd7d:76ee:e68f:a993::1
      ip6tables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
    '';
  };
}
