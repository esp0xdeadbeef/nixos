# Non-default boot specialization that trials the candidate cobalt router.
#
# The default boot entry runs `s-router-cobalt-prod` (see vm-host.nix). This
# specialization exists to A/B that by running `s-router-cobalt-new` in its
# place on the real trunk, with the production image left untouched on disk.
#
# BLOCKED (SAT, 2026-11-09, current state): the platform binding now reaches the
# containers, but the container runtime ignores the per-veth bridge, so the host
# side of the container WAN is still unattached and the trial has no egress.
#
# Proven working (the earlier "invariant under the renderer input" note was an
# artifact of `builtins.getFlake`, which ignores --override-input; the same
# check with the installable form fails when the module is deleted, which proves
# the module is on the evaluated path):
#   nix eval --override-input network-renderer-nixos path:... #     "path:...#nixosConfigurations.s-nodus.config.specialisation.
#      \"router-new-test\".configuration.containers.core.extraVeths"
#   -> cor-cbcoru-913,cor-wan-eca
#   ...extraVeths.\"cor-wan-eca\".hostBridge
#   -> br-wan
#
# Still broken: the generated container config does not carry it.
#   grep -c HOST_BRIDGE <spec>/etc/nixos-containers/core.conf  ->  0
# `nixos-containers` renders HOST_BRIDGE only for the primary `hostBridge`
# (`--network-bridge`); a bridge named on an `extraVeths` entry is dropped, so
# the model's host-side veth (cor-wan-eca) still comes up with no master and the
# container WAN keeps only a link-local address.
#
# Consequence: no egress in the trial, every SAT row stays NOT OK, and no honest
# evidence exists to flip any of them. Next fix belongs in the renderer: emit the
# host-side attachment itself (the veth as a bridge slave in the host's
# systemd-networkd config), not an extraVeths.hostBridge the runtime discards.
#
# Selecting it happens at boot time only (GRUB -> "router-new-test"), so a
# reboot always returns to the production shape. That is what makes the trial
# self-healing: whatever goes wrong -- no forwarding, no lease, a wedged guest
# the host cannot even reach -- the reboot restores production without anyone
# touching the site.
#
# The deadline is ADAPTIVE, because the two failure modes want opposite things:
#
#   egress broken -> get off the candidate quickly (default 10 min), since
#                    every extra minute is a site outage and there is nothing
#                    to watch on a dead box.
#   egress works  -> stay on the candidate much longer (default 2 h) so the
#                    live state can actually be inspected by hand: routes,
#                    conntrack, container state, tcpdump while it is flowing.
#
# "Egress" is the candidate's own connectivity, probed through the manager's
# tracked `vm-exec` bin (from the nixos-shell-vm-manager input) so it does not
# depend on the host's own path. The verdict and the
# deadline in force are logged on every poll, so a post-mortem can tell whether
# the box was ever healthy and which window applied.
#
# Everything the trial learns is written to /persist (not /run), because the
# point is to read it after the host has already rebooted back.
#
# Safety properties, in order of importance:
#
#   1. It is NOT the default entry. Nothing here can be reached by a plain
#      reboot of the production system.
#   2. The two router images conflict on the shared trunk ports (vm-host.nix
#      sets Conflicts=), so prod cannot start while the candidate runs. This
#      specialization also stops the carrier watcher from driving prod, which
#      would otherwise keep trying to start it and fight the candidate.
#   3. A reboot-loop guard: if the marker written just before the reboot is
#      still present, the host came back INTO the specialization, so it refuses
#      to reboot again and says so instead of looping.
{ config, lib, pkgs, inputs, relativeRepo, ... }:

let
  cfg = config.local.routerNewTest;

  stateDir = "/persist/router-new-test";
  logFile = "${stateDir}/host-state.log";
  rebootMarker = "${stateDir}/rebooted-at";
  startedAt = "${stateDir}/started-at";
  # Production generation recorded on every production boot; the trial guard
  # restores it before rebooting so a finished trial cannot boot itself again.
  baseGeneration = "${stateDir}/base-generation";

  prodInstance = "s-router-cobalt-prod";
  newInstance = "s-router-cobalt-new";

  # Guest exec comes from the nixos-shell-vm-manager flake input, not from a
  # privately built helper: the module already exports its operator commands
  # (vm-exec, vm-status, vm-logs, ...) as system.build, and vm-exec resolves the
  # per-VM QGA socket itself (`vm-exec VM COMMAND [ARG ...]`). Using the tracked
  # bin keeps this script in step with the manager's own QGA handling instead of
  # duplicating the socket path and socat plumbing here.
  # Egress is probed from inside the `core` container, not through QGA:
  # there is no VM any more, so `vm-exec` has no socket to talk to. Pinging
  # from core exercises the router's own forwarding/NAT, which is the thing
  # the deadline is supposed to be conditional on.
  nixosContainer = lib.getExe' pkgs.nixos-container "nixos-container";
  corePing = [
    nixosContainer
    "run"
    "core"
    "--"
    "/run/current-system/sw/bin/ping"
    "-c1"
    "-W5"
    "-n"
    "1.1.1.1"
  ];

  # Shared body for the state dump: the hypervisor-side facts that a
  # guest-side pcap cannot show.
  dumpState = ''
    set -u
    dir=${stateDir}
    mkdir -p "$dir"
    log=${logFile}

    {
      echo "=== $(date -Is) egress-window=${toString cfg.windowSeconds}s healthy-window=${toString cfg.egressOkWindowSeconds}s"
      echo "--- system"
      uptime
      echo "--- router containers"
      for c in core downstream-selector upstream-selector policy; do
        printf 'container@%s: %s\n' "$c" "$(systemctl is-active "container@$c.service" 2>/dev/null || true)"
      done
      echo "--- router container journal"
      for c in core downstream-selector upstream-selector policy; do
        echo "## $c"
        journalctl -b --no-pager -o short-iso -u "container@$c.service" 2>/dev/null | tail -15 || true
      done
      echo "--- capture volumes"
      du -sh /var/log/net-capture/* 2>/dev/null || echo "no captures"
      ls -la /var/log/net-capture/*/*.pcap* 2>/dev/null | tail -10 || true
      echo "--- bridges"
      for b in br-cobalt-lan br-cobalt-wan; do
        echo "## $b"
        ip -br link show master "$b" 2>/dev/null || echo "no members"
        bridge fdb show br "$b" 2>/dev/null | head -40 || true
      done
      echo "--- taps"
      ip -br link 2>/dev/null | grep -E 'tap-(lan-trunk|wan)' || echo none
      echo "--- wan carrier"
      cat /sys/class/net/wan-carrier/carrier 2>/dev/null || echo unknown
    } >>"$log" 2>&1
  '';
in
{
  options.local.routerNewTest = {
    windowSeconds = lib.mkOption {
      type = lib.types.int;
      default = 10 * 60;
      description = ''
        Deadline for the candidate while its egress is BROKEN. Short on
        purpose: the site is down for as long as the candidate is booted, and
        a dead box is not worth watching.
      '';
    };

    egressOkWindowSeconds = lib.mkOption {
      type = lib.types.int;
      default = 2 * 60 * 60;
      description = ''
        Deadline for the candidate while its egress WORKS. Deliberately long so
        the live router can be inspected by hand (routes, conntrack, tcpdump
        while traffic flows). Still finite: a forgotten trial must return the
        site to the production image eventually.
      '';
    };

    probeIntervalSeconds = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "How often egress is probed and the deadline re-evaluated.";
    };

    verifyIntervalSeconds = lib.mkOption {
      type = lib.types.int;
      default = 120;
      description = "How often the candidate's health is recorded during the trial.";
    };
  };

  config = {
    # Production boots clear the loop-guard marker. Without this the marker
    # written before a trial's reboot would survive forever and permanently
    # disarm the deadline for every later trial.
    systemd.services.router-new-test-clear-marker = {
      description = "Clear the router-new-test reboot guard after a production boot";
      wantedBy = [ "multi-user.target" ];
      before = [ "${prodInstance}-vm.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
      };
      script = ''
        set -u
        # Remember the production generation so the trial guard can put the
        # host back on it before rebooting. Without this the guard rebooted
        # into the specialization again (the profile still pointed at it) and
        # a trial could never end on its own.
        # Only a production boot may record the base generation: this unit also
        # runs inside the trial, and on 2026-11-09 it wrote the *trial* path
        # here, so the guard "restored" the trial and the box looped.
        cur=$(readlink -f /run/current-system)
        case "$cur" in
          *router-new-test*) : ;;
          *) echo "$cur" >${baseGeneration} ;;
        esac
        marker=${rebootMarker}
        if [ -e "$marker" ]; then
          echo "clearing router-new-test reboot marker from $(cat "$marker" 2>/dev/null || echo unknown)"
          rm -f "$marker"
        fi
      '';
    };

    specialisation.router-new-test.configuration = {
      system.nixos.tags = [ "router-new-test" ];

      # No QEMU envelope for this trial: the candidate is realized as NixOS
      # containers on this host. Drop both VM instances so nothing starts a
      # guest, and empty the carrier watcher so it cannot start one either.
      # Turn the VM manager off outright. Emptying the instance lists is not
      # enough: the module asserts that at least one instance is enabled and
      # that every carrier control references one, so "no VMs" has to mean the
      # manager itself is not configured.
      services.nixosShellVmManager.enable = lib.mkForce false;

      # The rendered container configuration bind-mounts /run/secrets/devices
      # into every container. sops-nix only creates the directories it has
      # secrets for, so on a host that never had that tree the mount source did
      # not exist and systemd-nspawn refused to start EVERY container:
      #
      #   systemd-nspawn: Failed to clone /run/secrets/devices/: No such file
      #   or directory
      #
      # Measured on the 2026-11-09 trial: 14 containers failed, then all came
      # up once the directory existed. It is a mount point the platform must
      # provide, so it is declared here rather than left to sops' side effects.
      # NOTE: tmpfiles is the wrong mechanism here. Measured on 2026-11-09:
      # `run-secrets.d.mount` (sops' tmpfs) is mounted AFTER
      # systemd-tmpfiles-setup has run, so a `d` entry is hidden by the mount
      # and /run/secrets/devices is absent at boot. The directory has to be
      # created once sops is up and before any container starts.
      systemd.services.s-nodus-secret-dirs = {
        description = "Provide the secret mount points the rendered containers bind";
        after = [ "sops-install-secrets.service" ];
        before = [ "container@.service" ];
        wants = [ "sops-install-secrets.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          mkdir -p /run/secrets/devices
          chmod 0750 /run/secrets/devices
        '';
      };

      # Realize the candidate's containers directly on this host by importing
      # the same rendered model the VM used, but WITHOUT vmNics: with an empty
      # NIC list vmNicsPlatformBinding returns null, so the renderer emits no
      # VM NIC binding and the module applies as host config instead of an
      # image. The deployment host in prod-network/testing/inventory-cobalt.nix
      # supplies this host's real ports (mxl_lan0 trunk, eth1 WAN).
      imports = [
        # The dumper now runs on THIS host, because the router's containers do.
        # It used to be enabled inside the s-router-cobalt-new guest, which no
        # longer boots; without this the trial would run with no pcaps at all.
        # The module watches the host-side container veths (ve-<name>).
        (relativeRepo.module "library/10-vms/nixos-shell-vm/host-config-routers-without-network/router-capture.nix")

        (import ../../virtual-machine/nixos-shell-vm/s-router-cobalt-new/renderers.nix {
          inherit inputs lib relativeRepo;
          controlPlaneModelInput = inputs.network-control-plane-model;
          networkRealizationModelInput = inputs.network-realization-model;
          nixosRendererInput = inputs.network-renderer-nixos;
          nebulaRendererInput = inputs.network-renderer-nebula;
          wireguardRendererInput = inputs.network-renderer-wireguard;
          system = "aarch64-linux";
          vmNics = [ ];
          # The realization target is the HOST. These containers run here, so
          # the inventory deployment host and every node's `host` must be
          # s-nodus -- not s-router-cobalt-new, which only named the QEMU
          # envelope. Keying it to the VM name would emit a deployment host
          # for a machine that no longer exists.
          hostName = "s-nodus";
          modelSource = relativeRepo.sourceModule "prod-network/testing";
          selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-cobalt-new/default.nix";
          # Same model the VM used: cobalt site, testing (latest network-*)
          # inputs. Cobalt-specific filenames, not the s-router-prod defaults.
          intentFileName = "intent-cobalt.nix";
          inventoryFileName = "inventory-cobalt.nix";
        })
      ];

      # The renderer emits the cobalt Nebula overlay for the core container,
      # which needs the overlay PKI. In the VM these secrets came from the
      # s-router-cobalt-new host module; this boot entry imports the renderer
      # without that host module, so without this the profile service fails
      # with "cannot stat /run/secrets/nebula-profile-core-vpn-garnet-cobalt-*"
      # and switch-to-configuration aborts the whole activation.
      sops.secrets =
        lib.genAttrs
          [
            "nebula-profile-core-vpn-garnet-cobalt-ca-crt"
            "nebula-profile-core-vpn-garnet-cobalt-crt"
            "nebula-profile-core-vpn-garnet-cobalt-key"
            "garnet-lighthouse-endpoint4"
          ]
          (_: {
            sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-garnet.yaml";
            format = "yaml";
          })
        # The rendered containers bind the SOPS-materialized device secrets and
        # the WAN MAC, exactly like the VM shape does in
        # s-router-cobalt-new/default.nix. That module is the VM image, so this
        # boot entry cannot import it; without these declarations sops never
        # creates /run/secrets/devices/<id> or /run/secrets/cobalt-wan-mac and
        # every container fails on its bind mount (measured 2026-11-09).
        //
        (
          let
            deviceDir = relativeRepo.sourceModule "prod-network/testing/secrets/devices";
            deviceSopsDir = relativeRepo.sourcePath "prod-network/testing/secrets/devices";
            deviceIds = map
              (name: lib.removeSuffix ".sops.yaml" name)
              (builtins.filter
                (name: lib.hasSuffix ".sops.yaml" name)
                (builtins.attrNames (builtins.readDir deviceDir)));
          in
          (lib.listToAttrs (
            map
              (id: {
                name = "cobalt-device-${id}";
                value = {
                  sopsFile = "${deviceSopsDir}/${id}.sops.yaml";
                  key = "mac";
                  format = "yaml";
                  path = "/run/secrets/devices/${id}";
                };
              })
              deviceIds
          ))
          // (lib.listToAttrs (
            builtins.concatMap
              (name:
                map
                  (entry: {
                    name = "cobalt-${name}-${entry.path}";
                    value = {
                      sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-vpn-${name}-fields.yaml";
                      key = entry.field;
                      path = "/run/secrets/${name}-${entry.path}";
                    };
                  })
                  [
                    { field = "privateKey"; path = "private-key"; }
                    { field = "endpoint"; path = "endpoint"; }
                    { field = "presharedKey"; path = "preshared-key"; }
                    { field = "publicKey"; path = "public-key"; }
                  ])
              [ "onyx" "opal" ]
          ))
          // {
            # The AP units read this one, not the containers: without it every
            # ap-conf-* unit dies with "open /run/secrets/cobalt-wifi: no such
            # file" and the WiFi AP never comes up (measured 2026-11-09).
            "cobalt-wifi" = {
              sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-wifi.yaml";
              key = "";
              path = "/run/secrets/cobalt-wifi";
            };

            "cobalt-wan-mac" = {
              sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-wan-mac.yaml";
              key = "mac";
              format = "yaml";
              path = "/run/secrets/cobalt-wan-mac";
            };
          }
        );

      local.routerCapture.enable = true;

      # Resolve the L2 collision instead of warning about it. The rendered
      # container target enslaves the two physical ports to br-lan-trunk and
      # br-wan; cobalt-bridges.nix (written for the QEMU envelope) enslaved the
      # same ports to br-cobalt-lan / br-cobalt-wan. Two .network files
      # matching one NIC means networkd applies whichever it likes, so instead
      # of warning, point the legacy units at the SAME bridges the rendered
      # target uses. One owner per port, no ambiguity.
      systemd.network.networks."10-mxl_lan0".networkConfig.Bridge = lib.mkForce "br-lan-trunk";
      systemd.network.networks."10-eth1".networkConfig.Bridge = lib.mkForce "br-wan";

      # Host management stays on vlan30. It is the host's own underlay
      # address (10.2.30.100) and the path nebula/ssh use, and vlan30 is fed by
      # the access jack on mxl_lan3 as well as cobalt-lan.30 -- so it keeps
      # working and must NOT be taken away as part of this trial.

      _module.args.sRouterProdProfile = {
        modelSource = relativeRepo.sourceModule "prod-network/testing";
        labSelector = null;
        productionSelector = "s-nodus";
      };

      # Hand the candidate to the carrier watcher instead of starting it here.
      # The manager asserts that a carrier-controlled instance never also sets
      # activation.startOnBoot, and that is the right division: the watcher
      # starts the candidate when the WAN transceiver is present and stops it
      # when the module is pulled, which is exactly the production behaviour we
      # want to reproduce while testing.
      #
      # Production is dropped from the watcher's instance list in the same
      # statement, so it is neither started by the watcher nor on boot (its
      # startOnBoot is already false in the base configuration). The shared
      # trunk ports are protected by the Conflicts= the manager sets between the
      # two images, so starting the candidate stops prod.


      systemd.services.router-new-test-banner = {
        description = "Announce the router-new-test trial";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = false;
        };
        script = ''
          set -u
          mkdir -p ${stateDir}
          date +%s >${startedAt}
          {
            echo "=== trial start $(date -Is)"
            echo "candidate:  ${newInstance}"
            echo "production: ${prodInstance} (stopped for this boot)"
            echo "deadline:   ${toString cfg.windowSeconds}s if egress is broken,"
            echo "            ${toString cfg.egressOkWindowSeconds}s if egress works"
            echo "captures:   in the candidate guest, /var/log/net-capture (on its state disk)"
            echo "generation: $(readlink -f /nix/var/nix/profiles/system 2>/dev/null || echo unknown)"
          } >>${logFile} 2>&1
        '';
      };

      # Record whether the candidate ever came up. A trial that produced no
      # traffic is only diagnosable if the log says whether the guest was ever
      # healthy, so this is sampled rather than only logged at the end.
      systemd.services.router-new-test-verify = {
        description = "Record candidate router health during the trial";
        path = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.nixos-container
          pkgs.systemd
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = false;
          TimeoutStartSec = "60s";
        };
        script = ''
          set -u
          ${dumpState}
          {
            echo "--- candidate health"
            printf 'active: %s\n' "$(systemctl is-active ${newInstance}-vm 2>/dev/null || true)"
            printf 'failed: %s\n' "$(systemctl is-failed ${newInstance}-vm 2>/dev/null || true)"
            systemctl show ${newInstance}-vm.service \
              -p NRestarts -p ActiveEnterTimestamp -p SubState 2>/dev/null || true
            printf 'egress: %s\n' "$(timeout 90 ${lib.escapeShellArgs corePing} >/dev/null 2>&1 && echo ok || echo broken)"
          } >>${logFile} 2>&1
        '';
      };

      systemd.timers.router-new-test-verify = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "3min";
          OnUnitActiveSec = "${toString cfg.verifyIntervalSeconds}s";
          Unit = "router-new-test-verify.service";
          Persistent = false;
        };
      };

      # The self-healing part. Polls instead of using a fixed deadline so the
      # window can follow the candidate's actual state: short while egress is
      # broken, long while it works.
      systemd.services.router-new-test-reboot = {
        description = "End the router-new-test trial and reboot into production";
        path = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.nix
          pkgs.nixos-container
          pkgs.systemd
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = false;
          TimeoutStartSec = "180s";
        };
        script = ''
          set -u
          marker=${rebootMarker}
          if [ -e "$marker" ]; then
            echo "router-new-test: marker present since $(cat "$marker" 2>/dev/null || echo unknown);" \
              "the host booted back into the specialization, refusing to reboot again" >>${logFile}
            exit 0
          fi

          start=$(cat ${startedAt} 2>/dev/null || true)
          if [ -z "$start" ]; then
            # The banner may not have run yet; fall back to boot time so a
            # candidate that never reaches multi-user still gets a deadline.
            start=$(( $(date +%s) - $(cut -d. -f1 /proc/uptime) ))
          fi
          now=$(date +%s)
          elapsed=$(( now - start ))

          if timeout 90 ${lib.escapeShellArgs corePing} >/dev/null 2>&1; then
            egress=ok
            deadline=${toString cfg.egressOkWindowSeconds}
          else
            egress=broken
            deadline=${toString cfg.windowSeconds}
          fi

          printf '%s router-new-test egress=%s elapsed=%ss deadline=%ss\n' \
            "$(date -Is)" "$egress" "$elapsed" "$deadline" >>${logFile}

          if [ "$elapsed" -lt "$deadline" ]; then
            exit 0
          fi

          ${dumpState}
          date +%s >"$marker"
          {
            echo "--- trial end"
            echo "egress at end: $egress (deadline ''${deadline}s, elapsed ''${elapsed}s)"
            echo "rebooting to the default boot entry (production)"
            echo "reboot requested at $(date -Is)"
          } >>${logFile} 2>&1

          # Derive the production generation from the profile history instead
          # of trusting one file: the newest system-*-link whose closure is not
          # a router-new-test build. Self-healing even if a stale/incorrect
          # base-generation file is present.
          base=""
          for link in $(ls -1dt /nix/var/nix/profiles/system-*-link 2>/dev/null); do
            target=$(readlink -f "$link" 2>/dev/null || true)
            case "$target" in
              "" | *router-new-test*) continue ;;
            esac
            base=$target
            break
          done
          if [ -z "$base" ]; then
            base=$(cat ${baseGeneration} 2>/dev/null || true)
          fi
          if [ -n "$base" ] && [ -d "$base" ]; then
            echo "restoring production generation $base before rebooting"
            nix-env -p /nix/var/nix/profiles/system --set "$base" || echo "WARNING: could not restore $base"
          else
            echo "WARNING: no recorded production generation; reboot would stay on the specialization"
          fi

          echo "router-new-test: egress=$egress, ''${elapsed}s elapsed >= ''${deadline}s; rebooting to the default entry"
          systemctl reboot
        '';
      };

      systemd.timers.router-new-test-reboot = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          # Poll from early boot: a candidate that never boots must still return
          # the site to production once the broken-egress window expires.
          OnBootSec = "60s";
          # OnUnitActiveSec does NOT re-arm for a Type=oneshot service that
          # runs and exits: measured on 2026-11-09, the trial ran 8624s against
          # a 600s deadline and only rebooted when an unrelated activation
          # happened to start the unit again. OnUnitInactiveSec is relative to
          # the previous run finishing, which is what a poll loop needs.
          OnUnitInactiveSec = "${toString cfg.probeIntervalSeconds}s";
          Unit = "router-new-test-reboot.service";
          Persistent = false;
        };
      };
    };
  };
}
