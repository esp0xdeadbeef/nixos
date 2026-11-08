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
# Each capture point is the host side of a container's veth pair. NixOS names
# that interface `ve-<container>` (nixos-containers.nix: ifaceHost=ve-$INSTANCE),
# so `ve-core` is exactly the boundary of the core container. Additional veths
# carry the renderer's own names (`ve-<container>-<suffix>`), which is why the
# interface set is resolved at runtime rather than hardcoded here.
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
        container matching one of them contributes its host-side veth
        (`ve-<container>` and `ve-<container>-*`) to this capture point.
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
    policy.containers = [ "policy-*" ];
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
      pkgs.nixos-container
      pkgs.tcpdump
    ];
    serviceConfig = {
      Type = "simple";
      # The manager's health check is "no failed units in the guest", so a
      # capture that cannot find its interfaces yet must retry in place rather
      # than fail the unit and mark a working router degraded.
      Restart = "always";
      RestartSec = "5s";
      Nice = 10;
    };
    script = ''
      set -u
      dir=${cfg.directory}/${name}
      mkdir -p "$dir"

      resolve() {
        ifaces=()
        containers=()
        for c in $(nixos-container list 2>/dev/null || true); do
          case "$c" in
            ${casePattern spec}) containers+=("$c") ;;
          esac
        done
        for c in "''${containers[@]-}"; do
          for p in /sys/class/net/*; do
            n=$(basename "$p")
            case "$n" in
              "ve-$c" | "ve-$c"-*) ifaces+=("$n") ;;
            esac
          done
        done
      }

      while :; do
        resolve
        if [ "''${#ifaces[@]}" -eq 0 ]; then
          echo "no veth yet for containers (${casePattern spec}); retrying"
          sleep 10
          continue
        fi

        args=()
        for i in "''${ifaces[@]}"; do
          args+=(-i "$i")
        done
        echo "capturing at hop ${name} on: ''${ifaces[*]}"

        # -e keeps the link-layer header so VLAN tags are visible in the pcap;
        # -s 128 keeps headers plus an address, which is what route/NAT/policy
        # analysis needs, at a fraction of the disk. -C/-W make a bounded ring:
        # at most $((fileSizeMb * fileCount)) MiB per hop, so a forgotten trial
        # can never fill the state disk.
        ${lib.getExe pkgs.tcpdump} -n -tttt -e -s ${toString cfg.snaplen} \
          "''${args[@]}" -C ${toString cfg.fileSizeMb} -W ${toString cfg.fileCount} \
          -w "$dir/${name}.pcap" \
          || echo "tcpdump at hop ${name} exited; restarting"
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
