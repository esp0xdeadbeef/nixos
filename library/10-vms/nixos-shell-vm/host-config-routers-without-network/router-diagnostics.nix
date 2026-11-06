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

  # One probe, run inside the core container. The guest's own namespace has no
  # `wan`/`mgmt` and no NAT, so every fact that describes the router has to be
  # read there; and one `nixos-container run` is far cheaper than six, each of
  # which sets up a namespace and can exceed the unit's start timeout.
  coreProbe = pkgs.writeShellScript "router-core-probe" ''
    for iface in wan mgmt; do
      a=$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | head -1)
      printf 'addr-%s=%s\n' "$iface" "''${a:-none}"
    done
    printf 'gateway=%s\n' "$(ip -4 route show default 2>/dev/null | awk '/^default/ {print $3; exit}')"
    printf 'forwards=%s\n' "$(unbound-control list_forwards 2>/dev/null | head -1)"
    w=$(ip -4 -o addr show dev wan 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
    printf 'conntrack=%s\n' "$(wc -l < /proc/net/nf_conntrack 2>/dev/null)"
    printf 'wan-snat=%s\n' "$(grep -c "$w" /proc/net/nf_conntrack 2>/dev/null)"
  '';

  # Everything the checks need, resolved at build time so the script does not
  # depend on the runtime PATH of a minimal systemd unit.
  tools = with pkgs; [
    curl
    dig
    gnugrep
    gawk
    iproute2
    iputils
    procps
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

        # Timer-driven only. A diagnostics unit must never sit on the boot
        # path: `wantedBy = multi-user.target` plus `wants = network-online`
        # pulls in systemd-networkd-wait-online, and a router guest that manages
        # carrier-less bridges can stall there long enough that the guest never
        # reaches "running" — which is how a trial left the site without a
        # router. The timer below samples the same state shortly after boot.
        after = [ "container@core.service" ];

        path = tools;

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = false;
          TimeoutStartSec = "90s";
          Nice = 10;
        };

        script = ''
          set -u
          exec >>${logFile} 2>&1

          stamp() { printf '%s %s\n' "$(date -Is)" "$*"; }

          stamp "=== router-selftest start (hostname=$(cat /etc/hostname)) ==="

          # 1. Everything the router itself knows: WAN/mgmt addresses, default
          #    gateway, resolver forwarders, and how many conntrack entries exist
          #    and are translated to the WAN address. A client flow that is absent
          #    from conntrack never traversed this router.
          core=$(timeout 60 nixos-container run core -- ${coreProbe} 2>/dev/null || true)
          printf '%s\n' "$core" | while read -r line; do
            [ -n "$line" ] && stamp "core $line"
          done

          # 2. Name resolution through the modelled resolver, then through a
          #    public one. DNS succeeding while TCP fails (or the reverse) is the
          #    signature we are chasing, so record them separately. Query the
          #    modelled resolver by address: the guest's own /etc/resolv.conf is
          #    not what clients are told to use.
          dns_local=$(dig +short +time=3 +tries=1 @10.2.30.1 www.google.com 2>&1 | head -1)
          dns_public=$(dig +short +time=3 +tries=1 @1.1.1.1 www.google.com 2>&1 | head -1)
          stamp "dig-modeled=10.2.30.1 ''${dns_local:-<empty>}"
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

          # Diagnostics must never be able to degrade the guest: the manager's
          # health check is literally "no failed units in the guest", so a
          # selftest that times out waiting for a container turns every trial
          # into a rollback of a working router. Report, never fail.
          exit 0
        '';
      };

      # Re-run hourly so a failure that only appears later is still captured on
      # the persisted log rather than lost with the volatile journal.
      systemd.timers.router-selftest = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "6min";
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
        after = [ "container@core.service" ];
        wants = [ "container@core.service" ];
        path = [ pkgs.nixos-container ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = false;
          # Never on the boot path (only the timer triggers this): `nixos-container
          # run` waits for the container's systemd, so as a multi-user.target job
          # it can hold the whole guest in "starting" — which is exactly what
          # happened, leaving the site without a router until the trial timed out.
          TimeoutStartSec = "60s";
        };
        script = ''
          set -u
          if ! nixos-container list 2>/dev/null | grep -qx core; then
            echo "core container is not up yet"
            exit 0
          fi
          # timeout(1) as well: a wedged container must not turn this unit into
          # the thing that never finishes.
          timeout 45 nixos-container run core -- /run/current-system/sw/bin/unbound-control \
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
