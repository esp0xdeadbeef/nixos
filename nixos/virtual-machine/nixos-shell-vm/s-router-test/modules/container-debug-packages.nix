{ pkgs }:

let
  common = with pkgs; [
    bind
    curl
    ethtool
    iproute2
    iputils
    jq
    lsof
    mtr
    netcat-openbsd
    nftables
    procps
    ripgrep
    socat
    strace
    tcpdump
    traceroute
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
