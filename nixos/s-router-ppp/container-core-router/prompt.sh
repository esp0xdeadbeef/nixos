#!/usr/bin/env bash

echo -e '“pppoe-wan-to-downstream should:\nreceive a /48 from the ISP\nuse one /64 from it for its own LAN\nroute the rest” but it does not, ipv4 AND ipv6 should be working, this is my config, fix it, check the imports in !!configuration.nix!!: ' ;

find . -type f -not -name '*.sh' -exec sh -c '
  echo
  echo "### FILE: $1 ###"
  cat "$1"
' sh {} \;

echo these are the logs of the last run:
ssh s-router-ppp sudo nixos-container run pppoe-wan-to-downstream -- journalctl -xe | tail -n30
echo this is my ip a output at this moment:
ssh s-router-ppp sudo nixos-container run pppoe-wan-to-downstream -- ip a

ssh s-router-ppp sudo nixos-container run pppoe-wan-to-downstream -- bash -c 'ping $(dig google.com @1.1.1.1 +short AAAA)'
