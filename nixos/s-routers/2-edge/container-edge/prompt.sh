#!/usr/bin/env bash
set -euo pipefail

echo "You are designing and debugging a SCALABLE multi-WAN policy-routing NixOS router (IPv4/IPv6)."
echo
echo "CONTEXT:"
echo "- This is a real running system. Basic IPv4/IPv6 works."
echo "- The problem is SCALING POLICY: multiple WANs, far-gateway selection, fwmark routing, and isolation."
echo "- Assume services like unbound/radvd/kea may be present; do not touch them unless required for policy correctness."
echo "- Upstreams may overlap in address space (e.g., same RFC1918 behind different WANs, multiple default routes, multiple VPNs)."
echo
echo "ROLE:"
echo "- Act as a senior Linux routing + firewall engineer AND NixOS module author."
echo "- You are responsible for deterministic routing semantics and isolation between WANs."
echo "- You must think in terms of: classification -> mark -> routing table -> NAT -> conntrack -> filtering."
echo
echo "NON-NEGOTIABLE DESIGN REQUIREMENTS:"
echo "1) Far gateway selection must be decided on the router (policy routing), not by clients."
echo "2) Each WAN interface (lan1010 and future WANs) is an OUTSIDE zone with strict anti-leak rules."
echo "3) Policy routing MUST NOT leak traffic to the wrong WAN (including return path leaks)."
echo "4) Marks must be consistent end-to-end: first packet mark -> conntrack restore -> correct routing table."
echo "5) Port forwards must be WAN-specific and must return via the same WAN (symmetric routing)."
echo "6) Load balancing is allowed only where explicitly configured and must be confined to a defined WAN-set."
echo "7) IPv4 and IPv6 must both follow the same policy model (separate tables ok, same semantics required)."
echo
echo "ABSOLUTE RULES (VIOLATION = WRONG ANSWER):"
echo "1. Do NOT guess. Every claim must cite evidence I provide (routes, rules, nft ruleset, sysctls, addr state, conntrack)."
echo "2. If you change ANY Nix file, you MUST output the FULL file content."
echo "3. Do NOT invent interface names, options, paths, or services."
echo "4. Explicitly verify configuration.nix imports when referencing module options."
echo "5. FIRST explain WHY the current design fails to scale (failure modes), THEN propose fixes."
echo "6. No vague language ('try', 'maybe', 'should')."
echo "7. Prefer minimal required change, but correctness beats minimal diff."
echo
echo "WHAT I WANT YOU TO PRODUCE (IN ORDER):"
echo "A) CURRENT STATE AUDIT"
echo "   - Identify the current routing domains: WANs, LANs, transit, VPNs."
echo "   - Enumerate existing route tables, ip rules, marks, nft chains, and NAT/port-forward behavior."
echo "   - Confirm whether marks survive (conntrack restore) and whether return traffic is symmetric."
echo
echo "B) FAILURE MODES (SCALING-RELATED ONLY)"
echo "   - Leakage: traffic egressing wrong WAN or returning wrong WAN."
echo "   - Overlap failure: identical prefixes behind multiple WANs causing incorrect selection."
echo "   - Port-forward asymmetry: DNAT works inbound, replies leave via wrong WAN."
echo "   - Load-balance bleed: flows assigned outside intended WAN-set."
echo "   - IPv6-specific pitfalls: RA/ND working but policy routing not applied or wrong table."
echo
echo "C) TARGET ARCHITECTURE (MUST BE IMPLEMENTABLE IN NIXOS)"
echo "   - Define zones: {LAN, TRANSIT, WAN:<name>}."
echo "   - Define marks and their meaning (bit layout or integer mapping)."
echo "   - Define routing tables per WAN and per WAN-set (for load balancing)."
echo "   - Define ip rules order, priorities, and exact match conditions."
echo "   - Define nftables chains: classify/mark, restore mark, filter, NAT, port-forward."
echo "   - State the invariants that prevent leakage."
echo
echo "D) MINIMAL REQUIRED CHANGES"
echo "   - Only propose the changes needed to reach the target model."
echo "   - Output FULL file(s) for any Nix changes."
echo
echo "E) VERIFICATION PLAN (DETERMINISTIC)"
echo "   - Provide exact commands to prove:"
echo "     * mark assignment on first packet"
echo "     * conntrack restores mark for subsequent packets"
echo "     * correct route table selection"
echo "     * symmetric return path for forwarded traffic"
echo "     * no leaks between WANs even with overlaps"
echo
echo "EVIDENCE I WILL PROVIDE (AUTHORITATIVE):"
echo "- Full Nix configs for networking, nftables, and any routing scripts/modules."
echo "- Output of:"
echo "  ip -br link"
echo "  ip -4 addr; ip -6 addr"
echo "  ip -4 route show table all; ip -6 route show table all"
echo "  ip -4 rule; ip -6 rule"
echo "  sysctl -a | egrep 'net.ipv4.conf|net.ipv6.conf|rp_filter|forwarding|accept_ra'"
echo "  nft list ruleset"
echo "  conntrack -L (filtered samples if large)"
echo "- A few real traffic examples (source IP -> dest IP -> intended WAN)."
echo
echo "OUTPUT FORMAT REQUIREMENTS:"
echo "- Start with a short failure summary focused on scaling."
echo "- Then bullet list: evidence -> conclusion."
echo "- Then architecture contract (marks/tables/rules/chains) in a structured list."
echo "- Then fixes with FULL file contents if changes are required."
echo "- Then verification commands and expected outcomes."
echo
echo "<<< BEGIN CONFIG FILES >>>"

find . -type f -not -name '*.sh' -exec sh -c '
  echo
  echo "### FILE: $1 ###"
  sed "s/\t/  /g" "$1"
' sh {} \;

echo
echo "<<< END CONFIG FILES >>>"
exit
echo
echo "<<< BEGIN RUNTIME EVIDENCE >>>"

echo
echo "<<< BEGIN DOWNSTREAM ROUTER EVIDENCE (downstream-router is PD client) >>>"

echo
echo "## journalctl (PD/RA related) - downstream-router"
ssh s-router-edge sudo nixos-container run downstream-router -- \
  journalctl -xe --no-pager | tail -n 80

echo
echo "## ip -6 addr - downstream-router"
ssh s-router-edge sudo nixos-container run downstream-router -- ip -6 addr

echo
echo "## ip -6 route - downstream-router"
ssh s-router-edge sudo nixos-container run downstream-router -- ip -6 route

echo
echo "## delegated routes (proto dhcp) - downstream-router"
ssh s-router-edge sudo nixos-container run downstream-router -- \
  ip -6 route show proto dhcp || true

echo
echo "## DHCPv6 client logs (common units) - downstream-router"
ssh s-router-edge sudo nixos-container run downstream-router -- \
  journalctl -u dhcpcd -u dhcpcd-ipv6 -u systemd-networkd --no-pager -n 200 || true

echo
echo "## lan1010 state - downstream-router"
ssh s-router-edge sudo nixos-container run downstream-router -- \
  networkctl status lan1010 --no-pager || true

echo
echo "## lan7 state (addressing/RA) - downstream-router"
ssh s-router-edge sudo nixos-container run downstream-router -- \
  ip -6 addr show dev lan7 || true

echo
echo "## routing advertisements / RA daemon status (if used) - downstream-router"
ssh s-router-edge sudo nixos-container run downstream-router -- \
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
ssh s-router-edge sudo nixos-container run downstream-router -- \
  ip a s lan1010 || true

echo
echo "## ping google dns"
ssh s-router-edge sudo nixos-container run downstream-router -- \
  ping -c 3 2001:4860:4860::8844 || true

echo
echo "<<< END DOWNSTREAM ROUTER TESTS >>>"
