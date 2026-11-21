# In-guest per-hop packet capture for the router forwarding path.
#
# The guest forwards client traffic through a chain of containers:
#
#   access-*  ->  downstream-selector  ->  core  ->  upstream-selector  -> WAN
#
# with the policy-* containers sitting beside that chain. When the candidate
# router has no connectivity there is usually no way to reach it and look --
# the trial exists precisely because the box may be unreachable. The evidence
# therefore has to be produced by the guest itself, and written somewhere that
# survives the host rebooting back to production. /var/log is persisted on the
# state disk (impermanence.nix), so mounting state.qcow2 is enough to read both
# the captures and the state log.
#
# Each capture point is the host side of a container's veth pair. The renderer
# does NOT name that interface `ve-<container>`: on 2026-11-09 the live names
# were `cor-wan-eca` / `cor-cbcoru-913`, and on 2026-11-21 they were
# `accc-cli-50f`, `accm-mgm-194`, `dows-p2pacc-8a9`, `upse-p2pcor-366`. A
# name-prefix guess therefore matched nothing (or matched by coincidence), which
# is recorded below.
#
# The interface set is resolved EXACTLY, not guessed: an interface inside a
# container names its host-side peer by that peer's ifindex in
# `/sys/class/net/<if>/iflink`, and a host ifindex is unique, so the mapping
# from container interface to host veth is exact and cannot collide across
# containers.
#
# The service also proves it is capturing. A unit that is `active (running)`
# while writing nothing is worse than a failed one: it is an artifact asserting
# a property no layer derived (AGENTS.md §8, §11-13). Measured 2026-11-21: four
# of five capture points had been retrying for twelve days, each still reported
# `active (running)`, and their directories had been empty since 2026-11-09.
#
# Container names are matched as GLOBS against `nixos-container list`, not as
# literal names: a rename in the model must not silently stop the capture and
# leave a "successful" trial with no evidence.
{ config, lib, pkgs, ... }:

let
  cfg = config.local.routerCapture;

  stageModule = lib.types.submodule {
    options.containers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = ''
        Container-name globs, matched against `nixos-container list`. Every
        container matching one of them contributes its host-side veth to this
        capture point; the veth is resolved exactly through `iflink`, not
        guessed from the name.
      '';
    };

    options.captureProbeSeconds = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = ''
        Override `captureProbeSeconds` for this hop. A hop that is legitimately
        idle (an overlay core nothing is using yet) grows no packets, so it must
        be able to widen or disable the probe instead of flapping. `null` uses
        the global value; `0` disables the probe for this hop.
      '';
    };
  };

  # The forwarding path, one entry per hop a packet traverses. Deliberately
  # globs: access-* and policy-* fan out per tenant and must not need editing
  # every time a tenant is added.
  defaultStages = {
    access.containers = [ "access-*" ];
    downstream.containers = [ "downstream-selector" ];
    core.containers = [ "core" "core-vpn-*" ];
    upstream.containers = [ "upstream-selector" ];
    # The container is named `policy`, not `policy-*`. The old glob matched no
    # container at all, so this hop could never resolve its interfaces.
    policy.containers = [ "policy" ];
  };

  # Containers the state log reports on, before any stage matches.
  globUnion = lib.concatMap (spec: spec.containers) (lib.attrValues cfg.stages);

  # One `case` alternative list per stage, e.g. `access-*|policy-*`.
  casePattern = spec: lib.concatStringsSep "|" spec.containers;

  mkCaptureService = name: spec: {
    description = "Packet capture at the ${name} hop of the router forwarding path";
    wantedBy = [ "multi-user.target" ];
    # Never on the boot path: capture must not delay the router coming up, and
    # the veths it watches only exist once the containers are started.
    after = [ "nixos-containers.target" ];
    path = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gawk
      pkgs.findutils
      pkgs.iproute2
      pkgs.nixos-container
      pkgs.tcpdump
    ];
    # A capture point that cannot resolve or cannot capture must keep retrying
    # (the guest health check is "no failed units"), but it must not present
    # itself as a healthy running service while writing nothing. Exiting
    # non-zero leaves the unit in `activating (auto-restart)`, which is the
    # honest state, and the start limit is disabled so it never degrades the
    # router by tripping into `failed`.
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "5s";
      Nice = 10;
    };
    script = ''
      set -u
      dir=${cfg.directory}/${name}
      mkdir -p "$dir"

      tmp="$(mktemp -d)"
      trap 'rm -rf "$tmp"' EXIT

      # Containers matching this hop's globs.
      hop_containers() {
        local c
        for c in $(nixos-container list 2>/dev/null || true); do
          case "$c" in
            ${casePattern spec}) printf '%s\n' "$c" ;;
          esac
        done
      }

      # Exact host veth for every interface of every hop container.
      #
      # Inside a container, /sys/class/net/<if>/iflink holds the ifindex of the
      # host-side peer, and a host ifindex is unique, so joining that index
      # against the host's interface list names the veth exactly. No name is
      # guessed, so a rename in the renderer cannot silently stop the capture.
      resolve() {
        local c
        ip -o link show \
          | sed -n 's/^\([0-9]\{1,\}\): \([^:@][^:@]*\).*/\1 \2/p' > "$tmp/host-index" || return 1
        : > "$tmp/peers"
        for c in $(hop_containers); do
          nixos-container run "$c" -- /bin/sh -c '
            for i in /sys/class/net/*; do
              n="''${i##*/}"
              [ "$n" = lo ] && continue
              [ -r "$i/iflink" ] || continue
              printf "%s %s\n" "$n" "$(cat "$i/iflink")"
            done' >> "$tmp/peers" 2>/dev/null || true
        done
        awk 'FNR==NR { host[$1] = $2; next }
             ($2 in host) { print host[$2] }' "$tmp/host-index" "$tmp/peers" | sort -u
      }

      # Wait for at least one peer, but not forever: a capture point that never
      # resolves reports failure instead of sitting active with an empty dir.
      waited=0
      while :; do
        mapfile -t ifaces < <(resolve)
        [ "''${#ifaces[@]}" -gt 0 ] && break
        if [ "$waited" -ge ${toString cfg.resolveTimeoutSeconds} ]; then
          echo "router-capture(${name}): no host veth for containers (${casePattern spec}) after ${toString cfg.resolveTimeoutSeconds}s" >&2
          exit 1
        fi
        sleep 5
        waited=$((waited + 5))
      done

      args=()
      for i in "''${ifaces[@]}"; do
        args+=(-i "$i")
      done

      ring_bytes() {
        local f total=0
        for f in "$dir/${name}".pcap*; do
          [ -e "$f" ] || continue
          total=$((total + $(stat -c %s "$f")))
        done
        printf '%s' "$total"
      }

      echo "capturing at hop ${name} on: ''${ifaces[*]}"

      while :; do
        # -e keeps the link-layer header so VLAN tags are visible in the pcap;
        # -s keeps headers plus an address, which is what route/NAT/policy
        # analysis needs, at a fraction of the disk. -C/-W make a bounded ring:
        # at most $((fileSizeMb * fileCount)) MiB per hop, so a forgotten trial
        # can never fill the state disk.
        before="$(ring_bytes)"
        ${lib.getExe pkgs.tcpdump} -n -tttt -e -s ${toString cfg.snaplen} \
          "''${args[@]}" -C ${toString cfg.fileSizeMb} -W ${toString cfg.fileCount} \
          -w "$dir/${name}.pcap" &
        capture_pid=$!

        # Prove it is capturing. A bound ring that never grows is not evidence,
        # and reporting a healthy service with an empty directory is how the
        # previous version misled a whole trial. Probe seconds are per-stage so
        # a legitimately idle hop can widen or disable the probe.
        probe=${toString (if spec.captureProbeSeconds != null then spec.captureProbeSeconds else cfg.captureProbeSeconds)}
        captured=1
        if [ "$probe" -gt 0 ]; then
          captured=0
          for _ in $(seq 1 "$probe"); do
            sleep 1
            [ "$(ring_bytes)" -gt "$before" ] && { captured=1; break; }
          done
        fi
        if [ "$captured" -ne 1 ]; then
          echo "router-capture(${name}): tcpdump wrote no packet in $${probe}s on ''${ifaces[*]}" >&2
          kill "$capture_pid" 2>/dev/null || true
          wait "$capture_pid" 2>/dev/null || true
          exit 1
        fi

        wait "$capture_pid" || true
        echo "router-capture(${name}): tcpdump exited; re-resolving and restarting"
        mapfile -t ifaces < <(resolve)
        args=()
        for i in "''${ifaces[@]}"; do
          args+=(-i "$i")
        done
        sleep 2
      done
    '';
  };

  stateScript = pkgs.writeShellScript "router-capture-state" ''
    set -u
    dir=${cfg.directory}
    mkdir -p "$dir"
    log="$dir/state.log"

    # Keep the log bounded; the pcaps matter more than a long tail of state.
    if [ -f "$log" ] && [ "$(wc -c <"$log")" -gt ${toString cfg.stateMaxBytes} ]; then
      mv -f "$log" "$log.1"
    fi

    {
      echo "=== $(date -Is) uptime=$(cut -d. -f1 /proc/uptime)s boot=$(cat /proc/sys/kernel/random/boot_id)"

      echo "--- links"
      ip -br link
      echo "--- addresses"
      ip -br address
      echo "--- routes"
      ip route show table all
      echo "--- rules"
      ip rule

      echo "--- containers"
      nixos-container list 2>/dev/null || true

      echo "--- container addresses"
      for c in $(nixos-container list 2>/dev/null || true); do
        printf '%s: ' "$c"
        timeout 10 nixos-container run "$c" -- ip -br address 2>/dev/null \
          | tr '\n' ' ' || printf 'unreachable'
        echo
      done

      echo "--- conntrack entries"
      wc -l </proc/net/nf_conntrack 2>/dev/null || echo none

      echo "--- nftables"
      nft list ruleset 2>/dev/null || echo none

      echo "--- connectivity"
      for t in 1.1.1.1 9.9.9.9; do
        printf 'ping %s: ' "$t"
        ping -c1 -W3 -n "$t" >/dev/null 2>&1 && echo ok || echo fail
      done
    } >>"$log" 2>&1
  '';
in
{
  options.local.routerCapture = {
    enable = lib.mkEnableOption "per-hop packet capture and state logging for the router forwarding path";

    directory = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/net-capture";
      description = ''
        Capture and state-log directory. The router guests persist /var/log on
        the state disk, so this is readable offline by mounting state.qcow2.
      '';
    };

    stages = lib.mkOption {
      type = lib.types.attrsOf stageModule;
      default = defaultStages;
      description = "Capture points, keyed by hop name.";
    };

    snaplen = lib.mkOption {
      type = lib.types.int;
      default = 128;
      description = "tcpdump -s. Headers plus a little payload.";
    };

    fileSizeMb = lib.mkOption {
      type = lib.types.int;
      default = 8;
      description = "tcpdump -C. Size of each ring file.";
    };

    fileCount = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "tcpdump -W. Ring length, so a hop is bounded to fileSizeMb*fileCount.";
    };

    resolveTimeoutSeconds = lib.mkOption {
      type = lib.types.int;
      default = 180;
      description = ''
        How long a capture point waits for its containers' veths before it gives
        up and exits non-zero. Containers need a couple of minutes to appear, so
        this is generous, but it is bounded on purpose: an unbounded wait is how
        four of five capture points sat `active (running)` with empty
        directories for twelve days (measured 2026-11-21).
      '';
    };

    captureProbeSeconds = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = ''
        After tcpdump starts, how long the ring may stay unchanged before the
        unit reports that it is not capturing and exits non-zero. A bounded ring
        that never grows is not evidence, and a service that claims to be
        running while writing nothing is a false assurance. `0` disables the
        probe; a per-stage `captureProbeSeconds` overrides this value.
      '';
    };

    stateIntervalSeconds = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "How often the link/route/container/probe state is appended.";
    };

    stateMaxBytes = lib.mkOption {
      type = lib.types.int;
      default = 1048576;
      description = "Rotate state.log once it grows past this size.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.tcpdump
      pkgs.nixos-container
    ];

    # One capture service per hop, plus the state logger. Merged into a single
    # attribute set: assigning `systemd.services` twice in the same module is a
    # duplicate-definition error, not a merge.
    systemd.services =
      (lib.mapAttrs'
        (
          name: spec: lib.nameValuePair "router-capture-${name}" (mkCaptureService name spec)
        )
        cfg.stages)
      // {
        router-capture-state = {
          description = "Record router link, route, container and connectivity state for offline analysis";
          path = [
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.gawk
            pkgs.iproute2
            pkgs.iputils
            pkgs.nftables
            pkgs.nixos-container
          ];
          serviceConfig = {
            Type = "oneshot";
            # A prebuilt script, so it goes through ExecStart: the `script`
            # option only accepts a string, and the unit's `path` still applies
            # to the process environment.
            ExecStart = stateScript;
            # A diagnostic must never become the reason the health check fails.
            RemainAfterExit = false;
            TimeoutStartSec = "120s";
          };
        };
      };

    systemd.timers.router-capture-state = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Containers need ~2.5 min to become addressable; before that every
        # `nixos-container run` in the log would say "unreachable".
        OnBootSec = "60s";
        OnUnitActiveSec = "${toString cfg.stateIntervalSeconds}s";
        Unit = "router-capture-state.service";
        Persistent = false;
      };
    };
  };
}
