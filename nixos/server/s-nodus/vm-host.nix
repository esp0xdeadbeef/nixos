{ config, lib, inputs, pkgs, vmImages, ... }:

# Minimal nixos-shell VM host for s-nodus (BPI-R4 Pro 4E, aarch64).
#
# WHY THIS IS NOT nixos-shell-vm-inventory.nix
# --------------------------------------------
# The shared server/nixos-shell-vm-inventory.nix imports
# prod-network/current/inventory-neon.nix (a protected production path) to
# derive one VLAN3 DNS record for an s-router-prod health check, and then
# enumerates the whole fleet's VMs.  s-nodus runs a single VM, so pulling in
# the entire fleet inventory (and the protected tree) would be both
# unnecessary and out of bounds.
#
# This file therefore declares exactly one instance -- s-router-cobalt-new --
# through the same nixos-shell-vm-manager module the servers use, so the
# runtime behaviour (persistent disk, QGA health check, start-on-boot,
# graceful shutdown) is identical.
#
# The image comes from `vmImages`, which the flake computes at the top level
# (see flake.nix).  Referencing self.nixosConfigurations.<vm> from inside
# s-nodus would be a cycle -- s-nodus is a member of that attrset, so forcing
# the VM image re-enters s-nodus and fails with `attribute '<vm>' missing`
# while building rootfsImage.
let
  vmName = "s-router-cobalt-new";

  qgaSocketFor = name: "/run/nixos-shell-vm-manager/${name}/qga.sock";

  guestAgentHealth =
    inputs.nixos-shell-vm-manager.packages.${pkgs.stdenv.hostPlatform.system}."qga-systemd-health";
in
{
  services.nixosShellVmManager = {
    enable = true;

    # The board has 4 cores; serialise image builds so a rebuild cannot
    # saturate it and starve the health polling.
    maxConcurrentBuilds = 1;

    persistentDirectory = "/persist/vm-persists";

    instances.${vmName} = {
      description = "cobalt site router, aarch64 port (nixos-shell)";

      image = vmImages.${vmName};

      activation.startOnBoot = true;

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
        qemuArguments = [
          "-chardev"
          "socket,id=qga0,path=${qgaSocketFor vmName},server=on,wait=off"
          "-device"
          "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"
        ];
      };
    };
  };
}
