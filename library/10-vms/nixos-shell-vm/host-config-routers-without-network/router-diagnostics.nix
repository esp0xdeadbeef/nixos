# In-guest router diagnostics.
#
# Two independent pieces, both opt-in per host:
#
#  * router-selftest records the checks that distinguish the failure modes we
#    actually hit (WAN lease missing, resolver SERVFAIL while a public resolver
#    answers, TCP egress timing out) into /var/log/router-selftest.log, which
#    impermanence.nix keeps on the persistent state disk. That makes the result
#    readable offline by mounting the qcow2 instead of needing a reachable
#    guest.
#
#  * router-dns-forwarders keeps a public-resolver forwarder installed in the
#    core container's unbound. This is a stopgap: the renderer only emits
#    `forward-addr` from dnsAuthority.rootForwarders, which needs
#    recursionMode "forwarding" plus a modelled named-core-resolver upstream
#    (the CPM synthesises those from DNS relations). Until the intent declares
#    core-dns -> upstream, unbound is a pure iterator and SERVFAILs while it
#    warms a cold root anchor. Deliberately off by default so a production
#    router never gets policy its intent does not model.
{ config, lib, pkgs, ... }:

let
  cfg = config.local.routerDiagnostics;

  logFile = "/var/log/router-selftest.log";

  # Public resolvers used when the modelled upstream is unreachable.
  dnsForwarders = [
    "1.1.1.1"
    "9.9.9.9"
  ];

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
  options.local.routerDiagnostics = {
    selftest = lib.mkEnableOption "the in-guest router self-test";

    ensureDnsForwarders = lib.mkEnableOption ''
      keeping a public-resolver forwarder installed in the core container's
      unbound, re-applied on a timer so it survives an unbound restart
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.selftest {
      systemd.services.router-selftest = {
        description = "Record guest-side DNS/WAN/TCP reachability for offline diagnosis";

        # Runs once the containers and their routes have had a chance to settle,
        # and again on a timer so a later failure is captured rather than only
        # the boot-time state.
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        path = tools;

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = false;
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
          #    public one. DNS succeeding while TCP fails (or the reverse) is the
          #    signature we are chasing, so record them separately.
          dns_local=$(dig +short +time=3 +tries=1 www.google.com 2>&1 | head -1)
          dns_public=$(dig +short +time=3 +tries=1 @1.1.1.1 www.google.com 2>&1 | head -1)
          stamp "dig-resolver=''${dns_local:-<empty>}"
          stamp "dig-public-1.1.1.1=''${dns_public:-<empty>}"

          # 3. TCP egress. Small bodies, short timeouts.
          for url in https://ifconfig.me http://checkip.amazonaws.com; do
            out=$(curl -m 12 -sS -o /dev/null -w '%{http_code} %{time_total}s' "$url" 2>&1 | tail -1)
            stamp "curl $url => ''${out:-<failed>}"
          done

          # 4. Record the busiest tasks so a wedged/spinning guest shows what was
          #    burning CPU instead of only the aftermath.
          stamp "top-cpu: $(ps -eo pcpu,comm --sort=-pcpu | sed -n '2,4p' | tr '\n' ' ' | tr -s ' ')"

          stamp "=== router-selftest end ==="
        '';
      };

      # Re-run hourly so a failure that only appears later is still captured on
      # the persisted log rather than lost with the volatile journal.
      systemd.timers.router-selftest = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "3min";
          OnUnitActiveSec = "1h";
          Unit = "router-selftest.service";
        };
      };
    })

    (lib.mkIf cfg.ensureDnsForwarders {
      # unbound-control state is runtime only, so an unbound restart (config
      # change, OOM, watchdog) drops the forwarder and local DNS would SERVFAIL
      # again until it warms a root anchor. Re-assert it on a timer.
      systemd.services.router-dns-forwarders = {
        description = "Ensure the core resolver forwards to reachable public resolvers";
        wantedBy = [ "multi-user.target" ];
        after = [ "container@core.service" ];
        wants = [ "container@core.service" ];
        path = [ pkgs.nixos-container ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = false;
        };
        script = ''
          set -u
          if ! nixos-container list 2>/dev/null | grep -qx core; then
            echo "core container is not up yet"
            exit 0
          fi
          nixos-container run core -- /run/current-system/sw/bin/unbound-control \
            forward ${lib.concatStringsSep " " dnsForwarders}
        '';
      };

      systemd.timers.router-dns-forwarders = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = "5min";
          Unit = "router-dns-forwarders.service";
        };
      };
    })
  ];
}
