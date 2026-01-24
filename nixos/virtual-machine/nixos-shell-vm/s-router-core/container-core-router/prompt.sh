#!/usr/bin/env bash
set -euo pipefail

echo "You are debugging a NixOS IPv4/IPv6 router setup."
echo
echo "ROLE:"
echo "- Act as a senior NixOS + Linux networking engineer."
echo "- Be strict, deterministic, and conservative."
echo "- Do NOT guess. Reason from evidence."
echo "- Prefer correctness over minimal diffs."
echo
echo "HARD RULES:"
echo "1. If you change ANY Nix file, respond with the FULL file content."
echo "2. If a file is correct, DO NOT modify it."
echo "3. Do NOT invent services, interfaces, or paths that are not present."
echo "4. Explicitly verify imports in configuration.nix."
echo "5. Explain WHY the current setup fails before proposing fixes."
echo "6. IPv4 AND IPv6 must work after your changes."
echo "7. No vague suggestions (\"try\", \"maybe\", \"it might\")."
echo
echo "GOAL (NON-NEGOTIABLE):"
echo "- Container pppoe-wan-to-downstream must receive an IPv6 PD (/48 or ISP size)"
echo "- Use exactly ONE /64 on lan1010"
echo "- Route remaining prefixes downstream"
echo "- Provide working IPv4 and IPv6"
echo
echo "<<< BEGIN CONFIG FILES >>>"

find . -type f -not -name '*.sh' -exec sh -c '
  echo
  echo "### FILE: $1 ###"
  sed "s/\t/  /g" "$1"
' sh {} \;

echo
echo "<<< END CONFIG FILES >>>"
echo
echo "<<< BEGIN RUNTIME EVIDENCE >>>"
echo
echo "## journalctl (tail)"
ssh s-router-ppp sudo nixos-container run pppoe-wan-to-downstream -- \
  journalctl -xe --no-pager | tail -n 50

echo
echo "## ip a"
ssh s-router-ppp sudo nixos-container run pppoe-wan-to-downstream -- ip a

echo
echo "## ip -6 addr"
ssh s-router-ppp sudo nixos-container run pppoe-wan-to-downstream -- ip -6 addr

echo
echo "## ip -6 route"
ssh s-router-ppp sudo nixos-container run pppoe-wan-to-downstream -- ip -6 route

echo
echo "## ping IPv6 (google)"
ssh s-router-ppp sudo nixos-container run pppoe-wan-to-downstream -- bash -c '
  set -e
  AAAA=$(dig google.com @1.1.1.1 +short AAAA | head -n1)
  if [ -z "$AAAA" ]; then
    echo "NO AAAA RECORD RESOLVED"
    exit 0
  fi
  echo "Pinging $AAAA"
  ping -c 3 "$AAAA"
'


echo
echo "## service status"
ssh s-router-ppp sudo nixos-container run pppoe-wan-to-downstream -- \
  systemctl status pppoe-pap dhcpcd-ipv6 v6-pd-generate kea-dhcp6 radvd --no-pager

echo
echo "## lan1010 IPv6 address"
ssh s-router-ppp sudo nixos-container run pppoe-wan-to-downstream -- \
  ip -6 addr show dev lan1010 || true

echo
echo "## DHCPv6 delegated routes"
ssh s-router-ppp sudo nixos-container run pppoe-wan-to-downstream -- \
  ip -6 route show proto dhcp || true

echo
echo "## kea-dhcp6 runtime config"
ssh s-router-ppp sudo nixos-container run pppoe-wan-to-downstream -- \
  cat /run/kea/kea-dhcp6.conf || true

echo
echo "## radvd runtime config"
ssh s-router-ppp sudo nixos-container run pppoe-wan-to-downstream -- \
  cat /run/radvd.conf || true

echo
echo "## DHCPv6 socket check (:547)"
ssh s-router-ppp sudo nixos-container run pppoe-wan-to-downstream -- \
  ss -ulpn | grep ':547' || true

echo
echo "## v6 services logs"
ssh s-router-ppp sudo nixos-container run pppoe-wan-to-downstream -- \
  journalctl -u v6-pd-generate -u kea-dhcp6 -u radvd --no-pager -n 200

echo starting tcpdump on s-router-ppp, while doing the rest of these commands:

timeout 10 ssh s-router-ppp sudo nixos-container run pppoe-wan-to-downstream -- tcpdump -i any ip6 -n &

echo
echo "<<< END RUNTIME EVIDENCE >>>"
echo
echo "<<< BEGIN DOWNSTREAM ROUTER TESTS >>>"
echo
echo "## ip a s lan1010"
ssh s-router-impermanence sudo nixos-container run downstream-router -- \
  ip a s lan1010 || true

echo
echo "## ping upstream google dns"
ssh s-router-impermanence sudo nixos-container run downstream-router -- \
  ping -c 3  2001:4860:4860::1 || true


echo
echo "<<< END DOWNSTREAM ROUTER TESTS >>>"




