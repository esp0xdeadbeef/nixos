# In-guest router self-test.
#
# Diagnosing "the router boots but nothing can egress" from the hypervisor is
# guesswork: the failure only exists inside the guest, and journald was
# volatile (see impermanence.nix, where /var/log is now persisted). This unit
# runs the checks that actually distinguish the failure modes and appends the
# result to a log on the persisted state disk, so a later
# `mount the qcow2 -> read /persist/var/log/router-selftest.log` shows what the
# guest saw, without needing the guest to be reachable.
#
# It is deliberately cheap and read-only: it never changes routing state.
{ config, lib, pkgs, ... }:

let
  logFile = "/var/log/router-selftest.log";

  # Everything the checks need, resolved at build time so the script does not
  # depend on the runtime PATH of a minimal systemd unit.
  tools = with pkgs; [
    curl
    dig
    gnugrep
    gawk
    iproute2
    iputils
  ];
in
{
  systemd.services.router-selftest = {
    description = "Record guest-side DNS/WAN/TCP reachability for offline diagnosis";

    # Runs once the containers and their routes have had a chance to settle,
    # and again on a timer so a later failure is captured rather than only the
    # boot-time state.
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "firewall.service" ];
    wants = [ "network-online.target" ];

    path = tools;

    serviceConfig = {
      Type = "oneshot";
      # Exiting (rather than RemainAfterExit) keeps the timer restarts honest.
      RemainAfterExit = false;
      # Never let a slow probe hold up boot.
      TimeoutStartSec = "180s";
      Nice = 10;
    };

    script = ''
      set -u
      exec >>${logFile} 2>&1

      stamp() { printf '%s %s\n' "$(date -Is)" "$*"; }

      stamp "=== router-selftest start (hostname=$(hostname)) ==="

      # 1. WAN lease. A router whose wan has no address cannot NAT anything,
      #    and every route assertion on the hypervisor still passes.
      for iface in wan mgmt; do
        addr=$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | head -1)
        stamp "addr $iface=''${addr:-<none>}"
      done

      gw=$(ip -4 route show default 2>/dev/null | awk '/^default/ {print $3; exit}')
      stamp "default-gateway=''${gw:-<none>}"

      # 2. Name resolution through the modelled resolver, then through a
      #    public one. DNS succeeding while TCP fails is the signature we are
      #    chasing, so record them separately.
      dns_local=$(dig +short +time=3 +tries=1 www.google.com 2>&1 | head -1)
      dns_public=$(dig +short +time=3 +tries=1 @1.1.1.1 www.google.com 2>&1 | head -1)
      stamp "dig-resolver=''${dns_local:-<empty>}"
      stamp "dig-public-1.1.1.1=''${dns_public:-<empty>}"

      # 3. TCP egress. Small bodies, short timeouts: a timeout here with a
      #    populated DNS answer above means forwarding, not resolution.
      for url in https://ifconfig.me http://checkip.amazonaws.com; do
        out=$(curl -m 12 -sS -o /dev/null -w '%{http_code} %{time_total}s' "$url" 2>&1 | tail -1)
        stamp "curl $url => ''${out:-<failed>}"
      done

      # 4. Promptly detect the spin/garbage case: record the busiest tasks so a
      #    wedged guest shows what was burning CPU.
      stamp "top-cpu: $(ps -eo pcpu,comm --sort=-pcpu | sed -n '2,4p' | tr '\n' ' ' | tr -s ' ')"

      stamp "=== router-selftest end ==="
    '';
  };

  # Re-run hourly so a failure that only appears later is still captured on the
  # persisted log rather than being lost with the volatile journal.
  systemd.timers.router-selftest = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "1h";
      Unit = "router-selftest.service";
    };
  };

  # Keep the log bounded on a box with a small state disk.
  systemd.services.router-selftest-logrotate = {
    description = "Trim the router self-test log";
    wantedBy = [ "multi-user.target" ];
    after = [ "router-selftest.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
    };
    script = ''
      set -u
      if [ -f ${logFile} ]; then
        tail -n 2000 ${logFile} > ${logFile}.tmp && mv ${logFile}.tmp ${logFile}
      fi
    '';
  };
}
