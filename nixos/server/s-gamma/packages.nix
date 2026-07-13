{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    conntrack-tools
    ethtool
    gron
    iproute2
    iptables
    iputils
    knot-dns
    netcat-openbsd
    neovim
    nftables
    socat
    strace
  ];
}
