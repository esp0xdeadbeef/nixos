{ inputs
, lib
, pkgs
, profiles
, ...
}:
{
  imports = [
    profiles.nixos.laptop.intel-workstation
    profiles.nixos.network.cobalt-wifi-client
    profiles.nixos.network.nebula-mesh
    profiles.nixos.vm-host.nixos-shell
    profiles.nixos.llm.ollama-base
    profiles.nixos.llm.open-webui
    profiles.nixos.containers.firefox-vnc
    profiles.nixos.ssh.password-login
    profiles.nixos.users.sudo-nopasswd

    inputs.disko.nixosModules.disko
    inputs.nixos-hardware.nixosModules.common-cpu-intel
    inputs.nixos-hardware.nixosModules.common-gpu-intel
    inputs.nixos-hardware.nixosModules.common-gpu-nvidia
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd

    ./1-custom-packages/burp-fix.nix
    ./hardware/audio-and-bluetooth.nix
    ./hardware/bootloader.nix
    ./hardware/cobalt-bridges.nix
    ./hardware/nighthawk-ap.nix
    ./hardware/hardware-configuration.nix
    ./hardware/impermanence.nix
    ./hardware/nvidia.nix
    ./hardware/sound-fix.nix
    ./hardware/swap-and-tmpfs.nix
    ./disko/build_disko.nix
    ./llms/ollama.nix
    ./lxc/bind-to-lxc.nix
    ./nixos-shell-servers
  ];

  local.network.private.enable = false;

  # mt7925u (Netgear A8000 AXE3000, 0846:9072) firmware reports a hw_path
  # without the 5GHz bit and no 6GHz capability; force the bands so the
  # tri-band chip exposes 2.4/5/6 GHz for AP use.
  boot.kernelPatches = [
    {
      name = "mt7925-force-5ghz";
      patch = ../../../patches/mt7925-force-5ghz.patch;
    }
  ];

  warnings = [
    "l-envil: systemd-hibernate.service disables systemd's user.slice freezer because hibernate froze immediately after freezing user.slice; remove this once the upstream/systemd sleep-stack issue is fixed."
  ];

  # Use the firmware's ACPI S4 path. The previous shutdown fallback wrote a
  # valid image, but hung before powering off after the BIOS update.
  environment.etc."systemd/sleep.conf.d/10-hibernate-platform-mode.conf".text = ''
    [Sleep]
    HibernateMode=platform
  '';

  systemd.services.systemd-hibernate.environment.SYSTEMD_SLEEP_FREEZE_USER_SESSIONS = "false";

  hardware.intelgpu.vaapiDriver = "intel-media-driver";

  local.laptop.monitorLayouts.samsungLu28r55Desk = {
    enable = true;
    left = "edid:37a85fea39fa278b";
    right = "edid:ccc5757174dd0f67";
    targetResolution = "3840x2160";
    internalScale = "0.75x0.75";
  };

  nixpkgs.config = {
    cudaCapabilities = [ "8.6" ];
    cudaForwardCompat = false;
  };

  users.users.deadbeef.extraGroups = [ "wheel" ];

  # Workaround: nixpkgs man-db manualPages default errors.
  documentation.man.man-db.enable = false;

  environment.systemPackages = [
    pkgs.mxbuild
  ];

  system.stateVersion = "24.11";
}
