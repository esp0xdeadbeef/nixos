{ profiles, ... }:
{
  imports = [
    profiles.nixos.nixos-shell-host.common

    ./vm-settings.nix
    ./restart-container.nix
    ./ssh.nix
    ./impermanence.nix
    ./persist-state-disk.nix
  ];

  # The VM manager's health check, `vm-exec`, and every diagnostic in this
  # repo talk to the guest through the QEMU guest agent over
  # org.qemu.guest_agent.0. Without an explicit enable the unit ships in the
  # closure but is never started, so a healthy guest is reported unhealthy and
  # the manager restores the previous image. Declare it here so every router
  # guest (cobalt-new, nixos lab, prod) answers on QGA by construction.
  services.qemuGuest.enable = true;
}
