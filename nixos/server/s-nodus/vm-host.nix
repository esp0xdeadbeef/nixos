{ config, lib, inputs, pkgs, vmImages, ... }:

# nixos-shell VM host for s-nodus (BPI-R4 Pro 4E, aarch64).
#
# Runs exactly one instance -- s-router-cobalt-new -- through the same
# nixos-shell-vm-manager module the servers use.  It is NOT the shared
# server/nixos-shell-vm-inventory.nix: that imports prod-network/current/
# inventory-neon.nix (a protected production path) to derive one VLAN3 DNS
# record for an s-router-prod health check and then enumerates the whole
# fleet's VMs.  s-nodus runs a single VM, so pulling in the entire fleet
# inventory (and the protected tree) would be both unnecessary and out of
# bounds.
#
# The image comes from `vmImages`, computed at the flake top level (see
# flake.nix).  Referencing self.nixosConfigurations.<vm> from inside s-nodus
# would be a cycle: s-nodus is a member of that attrset, so forcing the VM
# image re-enters s-nodus and fails with `attribute '<vm>' missing` while
# building rootfsImage.
let
  vmName = "s-router-cobalt-new";

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

    instances.${vmName} = {
      description = "cobalt site router, aarch64 port (nixos-shell)";

      image = vmImages.${vmName};

      # Started/stopped by carrierControls below, not unconditionally on boot.
      activation.startOnBoot = false;
      activation.restartOnGuestShutdown = true;

      healthCheck = {
        command = lib.escapeShellArgs [
          (lib.getExe guestAgentHealth)
          (qgaSocketFor vmName)
        ];
        timeoutSeconds = 10;
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
        # QGA device so the health check and graceful shutdown work.
        # The NICs (br-cobalt-lan / br-cobalt-wan) are set by the VM's own
        # virtualisation.qemu.networkingOptions.
        qemuArguments = [
          "-chardev"
          "socket,id=qga0,path=${qgaSocketFor vmName},server=on,wait=off"
          "-device"
          "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"
        ];
      };
    };

    # Start the cobalt router only while the WAN transceiver is present, the
    # same shape as s-sigma's `eno1-router-vms` rule on s-router-prod.
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
}
