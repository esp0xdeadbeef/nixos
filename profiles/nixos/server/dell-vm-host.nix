{ inputs
, lib
, name
, outPath
, pkgs
, profiles
, ...
}:
{
  imports = [
    inputs.hardware.nixosModules.common-cpu-intel
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

    "${outPath}/library/99-testing/enable-ssh-with-authorized-keys-and-add-NOPASSWD.nix"
    "${outPath}/modules/nixos/local-users.nix"
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

  local.laptop.xlayoutdisplayHotplug = {
    configLines = [
      "dpi=96"
    ];
    maxResolution = "1680x1050";
  };

  local.shell.zshPrompt.enable = true;

  networking.hostName = name;

  nixpkgs.hostPlatform = "x86_64-linux";

  sops.defaultSopsFile = "${outPath}/secrets/${name}-root.yaml";

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
