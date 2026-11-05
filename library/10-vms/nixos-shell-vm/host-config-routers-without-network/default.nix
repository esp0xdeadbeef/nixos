{ config
, lib
, pkgs
, profiles
, ...
}:
{
  imports = [
    profiles.nixos.nixos-shell-host.common

    ./vm-settings.nix
    ./restart-container.nix
    ./ssh.nix
    ./impermanence.nix
    ./persist-state-disk.nix
    ./router-diagnostics.nix
  ];


  # vhost tap attachment happens on the HYPERVISOR host, not in the guest:
  # the tap devices exist only in the host netns (see
  # nixos/server/*/…-vm-host or the server inventory). Keeping the unit here
  # would run it inside the guest, where tap-nicN is invisible, so it is
  # deliberately not declared in this module.
  config = {
    # The VM manager's health check, `vm-exec`, and every diagnostic in this
    # repo talk to the guest through the QEMU guest agent over
    # org.qemu.guest_agent.0. Without an explicit enable the unit ships in the
    # closure but is never started, so a healthy guest is reported unhealthy
    # and the manager restores the previous image. Declared here so every
    # router guest (cobalt-new, nixos lab, prod) answers by construction.
    services.qemuGuest.enable = true;

    # A router guest manages many links whose members are regularly
    # carrier-less (the LAN/WAN taps before their peer is up, dmz and vpn
    # planes, the management bridge). networkd treats every managed link as
    # required, so anything that pulls network-online.target inherits a wait
    # that can expire instead of succeeding. One online link is enough for a
    # target whose consumers order against the specific link they need.
    systemd.network.wait-online.anyInterface = true;
  };
}
