{ inputs
, lib
, name
, relativeRepo
, pkgs
, profiles
, ...
}:
{
  imports = [
    inputs.nixos-hardware.nixosModules.common-cpu-intel
    inputs.lanzaboote.nixosModules.lanzaboote
    inputs.sops-nix.nixosModules.sops

    profiles.nixos.boot.secure-boot-tools
    profiles.nixos.core
    profiles.nixos.base.maintenance
    profiles.nixos.desktop.i3
    profiles.nixos.editors.neovim
    profiles.nixos.hardware.clock-sync
    profiles.nixos.home-manager.deadbeef
    profiles.nixos.impermanence.module
    profiles.nixos.laptop.xlayoutdisplay-hotplug
    profiles.nixos.nix.flake-inputs
    profiles.nixos.nixpkgs.allow-unfree
    profiles.nixos.nixpkgs.local-overlays
    profiles.nixos.server.dell
    profiles.nixos.shell.zsh-prompt
    profiles.nixos.sops.persist-root-ssh
    profiles.nixos.ssh.password-login
    profiles.nixos.users.deadbeef-sops
    profiles.nixos.virtualization.libvirt
    profiles.nixos.virtualization.lxc
    profiles.nixos.virtualization.podman
    profiles.nixos.vm-host.nixos-shell

    profiles.nixos.nixos-shell-host.ssh-nopasswd
    (relativeRepo.module "modules/nixos/cuda-cache.nix")
    (relativeRepo.module "modules/nixos/local-users.nix")
  ];

  boot.loader.systemd-boot.configurationLimit = 12;

  # Dell iDRAC exposes an Avocent USB keyboard/mouse device on these R730 hosts.
  # Loading the matching input modules early avoids late udev module autoloading
  # while the kernel is already tearing down BPF/ftrace state during reboot.
  boot.kernelModules = lib.mkAfter [
    "hid_generic"
    "usbhid"
    "mac_hid"
    "mousedev"
    "evdev"
    "input_leds"
    "joydev"
  ];

  local.impermanence.extraUserDirectories = [
    "Documents"
  ];

  # The host Nix daemon builds GPU-enabled guest closures even though PCI
  # passthrough deliberately keeps the Nvidia driver out of the host closure.
  # Enable cached CUDA dependencies explicitly; guest packages that are not
  # published by the cache, such as the current Ollama output, still build once.
  local.nix.cudaCache.enable = true;

  local.laptop.xlayoutdisplayHotplug = {
    configLines = [
      "dpi=96"
    ];
    maxResolution = "1680x1050";
  };

  local.shell.zshPrompt.enable = true;

  networking.hostName = name;

  nixpkgs.hostPlatform = "x86_64-linux";

  sops.defaultSopsFile = relativeRepo.sourcePath "secrets/${name}-root.yaml";

  time.timeZone = "Europe/Amsterdam";

  users.users.deadbeef = {
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
  };

  environment.systemPackages = [
    pkgs.ethtool
  ];

  security.sudo = {
    enable = true;
    extraRules = [
      {
        groups = [ "wheel" ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
