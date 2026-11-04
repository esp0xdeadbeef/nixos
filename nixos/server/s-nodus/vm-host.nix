{ config, lib, inputs, pkgs, vmImages, vmNics, ... }:

# nixos-shell VM host for s-nodus (BPI-R4 Pro 4E, aarch64).
#
# Runs one instance -- s-router-cobalt-new -- through the same
# nixos-shell-vm-manager module the servers use.  (Tang used to be a second
# instance here; it is now a plain host container, see ./tang.nix.)
# It is NOT the shared
# server/nixos-shell-vm-inventory.nix: that imports prod-network/current/
# inventory-neon.nix (a protected production path) to derive one VLAN3 DNS
# record for an s-router-prod health check and then enumerates the whole
# fleet's VMs.  s-nodus runs its own instances, so pulling in the entire fleet
# inventory (and the protected tree) would be both unnecessary and out of
# bounds.
#
# The image comes from `vmImages`, computed at the flake top level (see
# flake.nix).  Referencing self.nixosConfigurations.<vm> from inside s-nodus
# would be a cycle: s-nodus is a member of that attrset, so forcing the VM
# image re-enters s-nodus and fails with `attribute '<vm>' missing` while
# building rootfsImage.
let
  # The managed cobalt router.  s-router-cobalt-prod is the production shape
  # (prod-network/prod, -prod pinned network-* inputs); s-router-cobalt-new is
  # the testing shape it replaced and is kept only as a rollback target, so it
  # is deliberately NOT carrier-managed or started on boot.
  vmName = "s-router-cobalt-prod";

  qgaSocketFor = name: "/run/nixos-shell-vm-manager/${name}/qga.sock";

  guestAgentHealth =
    inputs.nixos-shell-vm-manager.packages.${pkgs.stdenv.hostPlatform.system}."qga-systemd-health";

  # The WAN is the sfp2 SFP+ cage.  Its 10G MAC is not mainline/bound yet, so
  # there is no netdev with a carrier to key on.  The authoritative "is the
  # transceiver present" signal is the SFP `mod-def0` pin, which the kernel's
  # sfp driver reads; it is ACTIVE LOW, i.e. present == logic 0.
  #
  # carrierControls (like s-sigma's eno1 rule) watches
  # /sys/class/net/<iface>/carrier.  Bridge that to the SFP presence via a
  # dummy interface whose carrier follows mod-def0: down when no module,
  # up when one is seated.  This is a lifecycle/platform binding, not network
  # meaning.
  sfpPresenceScript = pkgs.writeShellApplication {
    name = "s-nodus-wan-carrier";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      iproute2
      kmod
      systemd
    ];
    text = ''
      set -euo pipefail

      dummy=wan-carrier
      # mod-def0 lines are named "mod-def0"; there is one per SFP cage.  The
      # sfp driver keeps those lines claimed, so their value is read from
      # debugfs instead of being requested with gpiod.
      poll=2

      mk_iface() {
        if ! ip link show "$dummy" >/dev/null 2>&1; then
          ip link add "$dummy" type dummy
        fi
      }

      # mod-def0 ACTIVE LOW: present => value 0 in /sys/kernel/debug/gpio.
      # Lines look like:
      #   gpio-1   (                    |mod-def0            ) in  hi IRQ ACTIVE LOW
      #   gpio-69  (                    |mod-def0            ) in  hi IRQ ACTIVE LOW
      # Two lines share the "mod-def0" name.  The DT says which is which:
      #   /sys/firmware/devicetree/base/sfp2/mod-def0-gpios -> pinctrl line 1
      #   /sys/firmware/devicetree/base/sfp1/mod-def0-gpios -> pinctrl line 69
      # and gpiochip0 (pinctrl_moore) is that controller, so on this board
      #   sfp2 (WAN)  = gpio-1
      #   sfp1        = gpio-69
      # i.e. the WAN cage is the LOWEST-numbered mod-def0 line.
      presence() {
        line=$(grep -E '\|mod-def0' /sys/kernel/debug/gpio 2>/dev/null \
          | sort -t- -k2 -n | head -1 || true)
        [ -n "$line" ] || { echo absent; return; }
        # state column reads "hi"/"lo"; mod-def0 is ACTIVE LOW, so a seated
        # module pulls the line low => present.
        if grep -qE 'in  lo' <<<"$line"; then echo present; else echo absent; fi
      }

      mk_iface
      ip link set "$dummy" up

      last=
      while true; do
        state=$(presence)
        if [ "$state" != "$last" ]; then
          if [ "$state" = present ]; then
            echo "$dummy: WAN transceiver present -> carrier on"
            ip link set "$dummy" carrier on || true
          else
            echo "$dummy: WAN transceiver absent -> carrier off"
            ip link set "$dummy" carrier off || true
          fi
          last=$state
        fi
        sleep "$poll"
      done
    '';
  };
in
{
  # Dummy interface carrier must be settable; the module is not autoloaded by
  # default on this kernel build.
  boot.kernelModules = [ "dummy" ];

  systemd.services.s-nodus-wan-carrier = {
    description = "Expose the sfp2 SFP presence as a carrier on wan-carrier";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = lib.getExe sfpPresenceScript;
      Restart = "always";
      RestartSec = "3s";
    };
  };

  services.nixosShellVmManager = {
    enable = true;

    # The board has 4 cores; serialise image builds so a rebuild cannot
    # saturate it and starve the health polling.
    maxConcurrentBuilds = 1;

    persistentDirectory = "/persist/vm-persists";

    # Both cobalt router images are managed so either can be started by name.
    # They share the trunk, so each conflicts with the other: systemd stops the
    # conflicting unit, giving the one-at-a-time semantics the shared
    # br-cobalt-lan / br-cobalt-wan ports require (running both duplicated every
    # MAC on the trunk and made the downstream flap as the guests fought over
    # the topology).
    #
    #   s-router-cobalt-prod  production shape  prod-network/prod + -prod pins
    #   s-router-cobalt-new   testing/rollback  prod-network/testing + main pins
    #
    # Only the prod instance is carrier-managed (see carrierControls below).
    # cobalt-new is never started on boot and never touched by the carrier
    # watcher; it is started by hand when testing a candidate.
    instances =
      lib.genAttrs
        [
          "s-router-cobalt-prod"
          "s-router-cobalt-new"
        ]
        (
          name:
          let
            other =
              if name == "s-router-cobalt-prod" then "s-router-cobalt-new" else "s-router-cobalt-prod";
          in
          {
            description =
              if name == "s-router-cobalt-prod" then
                "cobalt site router, aarch64 port, production shape (nixos-shell)"
              else
                "cobalt site router, aarch64 port, testing shape (nixos-shell)";

            image = vmImages.${name};

            # Never started unconditionally on boot. The prod instance is
            # started by carrierControls; the testing instance is started by
            # hand and must not race it at boot.
            activation.startOnBoot = false;
            activation.restartOnGuestShutdown = true;

            healthCheck = {
              command = lib.escapeShellArgs [
                (lib.getExe guestAgentHealth)
                (qgaSocketFor name)
              ];
              # The guest has to finish booting systemd + 15 containers before
              # it can answer on the QGA socket. The old 10s timeout regularly
              # expired while QEMU itself was healthy but the guest was still
              # starting, which read as a failed health check and triggered
              # another restart -- each one a visible link flap on the trunk.
              timeoutSeconds = 20;
              retries = 60;
              intervalSeconds = 2;
            };

            storage.persistentDisk = {
              enable = true;
              fileName = "state.qcow2";
              size = "8G";
            };

            runner = {
              stopGraceSeconds = 60;
              # Two instances attach to the same host bridge ports, so they
              # must never run together. `Conflicts=` is a [Unit] directive;
              # serviceConfig renders into [Service], where systemd ignores it
              # ("Unknown key 'Conflicts' in section [Service]"), so it is
              # set through the manager's unitConfig instead.
              unitConfig.Conflicts = [ "${other}-vm.service" ];
              # QGA device so the health check and graceful shutdown work.
              # The NICs (br-cobalt-lan / br-cobalt-wan) are set by the VM's own
              # virtualisation.qemu.networkingOptions.
              qemuArguments = [
                "-chardev"
                "socket,id=qga0,path=${qgaSocketFor name},server=on,wait=off"
                "-device"
                "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"
              ];
            };
          }
        );


    # Tang (NBDE) is no longer a nixos-shell VM: it runs as a plain NixOS
    # container on this host (./tang.nix), with its key database on /persist.
    # Keeping it off the carrier-control path is deliberate -- a booting laptop
    # must reach Tang to unlock its root disk, so it has to be up even when no
    # WAN transceiver is seated, which `containers.*` autoStart guarantees.

    # Start the cobalt router only while the WAN transceiver is present, the
    # same shape as s-sigma's `eno1-router-vms` rule on s-router-prod.
    # --- vhost tap attachment (host side) -------------------------------
    #
    # vhost NICs render as `-netdev tap,ifname=tap-<nicId>,vhost=on,queues=N`
    # because qemu rejects vhost/queues inside `-nic` and `-netdev bridge`. A
    # bare tap is NOT bridged by qemu, and the tap lives in THIS host netns, so
    # the attach must happen here (a guest-side unit cannot see it).
    #
    # `vmNics` (flake.nix) is the single source of truth for the map. The unit
    # polls because the tap only appears once qemu opened the netdev. It is
    # inert while a VM still uses `-nic bridge`, since nothing matches.

    carrierControls.wan-router-vms = {
      interface = "wan-carrier";
      requiredInterfaces = [
        "br-cobalt-lan"
        "br-cobalt-wan"
      ];
      instances = [ vmName ];
      pollIntervalSeconds = 5;
      description = "Start or stop the cobalt router VM from the WAN transceiver state";
    };
  };

  # vhost tap attachment lives at module top level: the taps exist in this
  # host netns, so the unit must not be nested under the VM manager option tree.
  systemd.services.vhost-tap-attach = {
    description = "Enslave vhost-net tap devices of the router VMs to their bridges";
    # /run/nixos-shell-vm-manager/... The taps are created by the VM's own
    # -netdev tap,ifname=... argument, i.e. AFTER the VM unit starts -- not at
    # boot. A boot-only oneshot therefore never sees them: it ran at 17:31 and
    # logged "tap-lan-trunk did not appear" three minutes before the trial
    # started the VM, so the guest's wan tap stayed unenslaved and got no DHCP
    # lease. Bind the attach to the VM units so it re-runs on every start.
    wantedBy = [ "s-router-cobalt-new-vm.service" "s-router-cobalt-prod-vm.service" ];
    after = [ "s-router-cobalt-new-vm.service" "s-router-cobalt-prod-vm.service" ];
    # NOTE: no `partOf`. PartOf propagates in BOTH directions: when this unit
    # is restarted during `nixos-rebuild switch`, systemd also stops/restarts
    # the listed VM units. That took the production cobalt router down for 13
    # minutes (23:39:57 -> 23:52:48 on 2026-11-04, no carrier trigger to bring
    # it back) while the host itself kept its internet connection. wantedBy +
    # after are enough to run the attach after each VM start.
    path = [
      pkgs.iproute2
      pkgs.coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -u

      attach() {
        tap="$1"
        bridge="$2"
        i=0
        while [ "$i" -lt 120 ]; do
          if ip link show dev "$tap" >/dev/null 2>&1; then
            ip link set dev "$tap" master "$bridge"
            ip link set dev "$tap" up
            echo "attached $tap -> $bridge"
            return 0
          fi
          i=$((i + 1))
          sleep 1
        done
        echo "NOTE: $tap did not appear (VM not using vhost, or not running)"
        return 0
      }
    ''
    + lib.concatMapStringsSep "\n"
      (
        nic: "attach ${lib.escapeShellArg "tap-${nic.nicId}"} ${lib.escapeShellArg nic.bridge}"
      )
      (lib.unique (lib.concatLists (lib.attrValues vmNics)));
  };
}
