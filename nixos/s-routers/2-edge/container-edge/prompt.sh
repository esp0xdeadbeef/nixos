#!/usr/bin/env bash
set -euo pipefail

echo "You are debugging a NixOS IPv4/IPv6 router setup."
echo
echo "CONTEXT:"
echo "- This is a real, failing system. The logs and runtime state below are authoritative."
echo "- Assume upstream (OPNsense) is already configured and reachable unless evidence proves otherwise."
echo "- Assume nothing works unless explicitly proven by the evidence."
echo
echo "ROLE:"
echo "- Act as a senior NixOS + Linux networking engineer."
echo "- You are responsible for correctness, not politeness."
echo "- Be strict, deterministic, and conservative."
echo "- Do NOT guess. Every claim must be grounded in evidence shown below."
echo "- Prefer correctness and protocol compliance over minimal diffs."
echo
echo "ABSOLUTE RULES (VIOLATION = WRONG ANSWER):"
echo "1. If you change ANY Nix file, you MUST respond with the FULL file content."
echo "2. If a file is correct, DO NOT modify it."
echo "3. Do NOT invent services, interfaces, options, paths, or assumptions."
echo "4. Explicitly verify and reference imports in configuration.nix."
echo "5. You MUST explain WHY the current setup fails before proposing fixes."
echo "6. After changes, IPv4 AND IPv6 MUST work end-to-end."
echo "7. No vague language (\"try\", \"maybe\", \"should\", \"it might\")."
echo "8. If information is missing, explicitly state what is missing and why it matters."
echo
echo "FAILURE-FIRST DEBUGGING REQUIREMENT:"
echo "- First, identify the exact failure mode(s) (routing, RA, DHCPv6-PD, sysctl, firewall, networkd, Kea, radvd)."
echo "- Then map each failure to concrete evidence (logs, routes, addresses, sockets)."
echo "- Only then propose the minimal REQUIRED fix."
echo

echo "GOAL (NON-NEGOTIABLE):"
echo "- 'downstream-router' must be the DHCPv6-PD client on interface lan1010."
echo "- 'downstream-router' must receive a delegated prefix via lan1010 that is larger than /53 (i.e., a shorter prefix length such as /56 or /48)."
echo "- 'downstream-router' must NOT consume more than one /64 for the lan1010 transit segment."
echo "- 'downstream-router' must carve out exactly ONE /64 from the delegated prefix for lan7 and advertise/serve it to lan7 clients."
echo "- 'downstream-router' must route any remaining delegated space as needed (or keep it available for future LANs), without breaking connectivity."
echo "- IPv4 connectivity MUST continue to work end-to-end."

echo
echo "OUTPUT FORMAT REQUIREMENTS:"
echo "- Start with a short, precise failure summary."
echo "- Then a bullet list mapping evidence -> conclusion."
echo "- Then fixes (if any), with full file contents."
echo "- If no changes are needed, explicitly state that and explain why."
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
echo "<<< BEGIN DOWNSTREAM ROUTER EVIDENCE (downstream-router is PD client) >>>"

echo
echo "## journalctl (PD/RA related) - downstream-router"
ssh s-router-impermanence sudo nixos-container run downstream-router -- \
  journalctl -xe --no-pager | tail -n 80

echo
echo "## ip -6 addr - downstream-router"
ssh s-router-impermanence sudo nixos-container run downstream-router -- ip -6 addr

echo
echo "## ip -6 route - downstream-router"
ssh s-router-impermanence sudo nixos-container run downstream-router -- ip -6 route

echo
echo "## delegated routes (proto dhcp) - downstream-router"
ssh s-router-impermanence sudo nixos-container run downstream-router -- \
  ip -6 route show proto dhcp || true

echo
echo "## DHCPv6 client logs (common units) - downstream-router"
ssh s-router-impermanence sudo nixos-container run downstream-router -- \
  journalctl -u dhcpcd -u dhcpcd-ipv6 -u systemd-networkd --no-pager -n 200 || true

echo
echo "## lan1010 state - downstream-router"
ssh s-router-impermanence sudo nixos-container run downstream-router -- \
  networkctl status lan1010 --no-pager || true

echo
echo "## lan7 state (addressing/RA) - downstream-router"
ssh s-router-impermanence sudo nixos-container run downstream-router -- \
  ip -6 addr show dev lan7 || true

echo
echo "## routing advertisements / RA daemon status (if used) - downstream-router"
ssh s-router-impermanence sudo nixos-container run downstream-router -- \
  systemctl status radvd --no-pager || true

echo
echo "<<< END DOWNSTREAM ROUTER EVIDENCE >>>"


exit 
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
echo "## ping google dns"
ssh s-router-impermanence sudo nixos-container run downstream-router -- \
  ping -c 3 2001:4860:4860::8844 || true



echo
echo "<<< END DOWNSTREAM ROUTER TESTS >>>"




