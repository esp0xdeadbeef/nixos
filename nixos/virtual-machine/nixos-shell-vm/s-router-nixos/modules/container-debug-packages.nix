{ pkgs }:

let
  common = with pkgs; [
    bind
    curl
    dig
    ethtool
    iproute2
    iputils
    jq
    lsof
    mtr
    netcat-openbsd
    nftables
    procps
    python3
    ripgrep
    socat
    strace
    tcpdump
    tmux
    traceroute
    tshark
  ];
in
{
  inherit common;

  endpoint = with pkgs; common ++ [
    avahi
  ];

  nebula = with pkgs; common ++ [
    nebula
  ];
}
