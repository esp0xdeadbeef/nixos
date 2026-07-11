{
  mail = {
    accounts = import ./mail/accounts.nix;
  };

  nixos = {
    base = {
      default = import ./nixos/base;
      common = import ./nixos/base/common.nix;
      maintenance = import ./nixos/base/maintenance.nix;
      system = import ./nixos/base/system.nix;
    };
    core = import ./nixos/core;
    boot = {
      clevis-tang-unlock = import ./nixos/boot/clevis-tang-unlock.nix;
      secure-boot-tools = import ./nixos/boot/secure-boot-tools.nix;
      usb-removable = import ./nixos/boot/usb-removable.nix;
    };
    desktop = {
      common = import ./nixos/desktop/common.nix;
      gnome = import ./nixos/desktop/gnome.nix;
      i3 = import ./nixos/desktop/i3.nix;
      sway = import ./nixos/desktop/sway.nix;
    };
    containers = {
      firefox-vnc = import ./nixos/containers/firefox-vnc.nix;
    };
    editors = {
      neovim = import ./nixos/editors/neovim;
    };
    packages = {
      workstation = import ./nixos/packages/workstation.nix;
    };
    nixpkgs = {
      allow-unfree = import ./nixos/nixpkgs/allow-unfree.nix;
      local-overlays = import ./nixos/nixpkgs/local-overlays.nix;
    };
    nix = {
      flake-inputs = import ./nixos/nix/flake-inputs.nix;
    };
    shell = {
      fish = import ./nixos/shell/fish.nix;
      zsh-prompt = import ./nixos/shell/zsh-prompt.nix;
    };
    home-manager = {
      deadbeef = import ./nixos/home-manager/deadbeef.nix;
    };
    hardware = {
      clock-sync = import ./nixos/hardware/clock-sync.nix;
    };
    ssh = {
      deadbeef-authorized-keys = import ./nixos/ssh/deadbeef-authorized-keys.nix;
      password-login = import ./nixos/ssh/password-login.nix;
    };
    network = {
      private = import ./nixos/network/private.nix;
      workstation = import ./nixos/network/workstation.nix;
    };
    server = {
      dell = import ./nixos/server/dell.nix;
      dell-vm-host = import ./nixos/server/dell-vm-host.nix;
    };
    sops = {
      persist-root-age-key-file = import ./nixos/sops/persist-root-age-key-file.nix;
      persist-root-ssh = import ./nixos/sops/persist-root-ssh.nix;
    };
    users = {
      deadbeef-sops = import ./nixos/users/deadbeef-sops.nix;
    };
    virtualization = {
      docker = import ./nixos/virtualization/docker.nix;
      host = import ./nixos/virtualization/host.nix;
      libvirt = import ./nixos/virtualization/libvirt.nix;
      lxc = import ./nixos/virtualization/lxc.nix;
      podman = import ./nixos/virtualization/podman.nix;
    };
    llm-clients = {
      cache = import ./nixos/llm-clients/cache.nix;
      agents = import ./nixos/llm-clients/agents.nix;
    };
    llm = {
      ollama-base = import ./nixos/llm/ollama-base.nix;
      open-webui = import ./nixos/llm/open-webui.nix;
    };
    impermanence = {
      module = args@{ config, lib, outputs, pkgs, ... }:
        let
          persistPath = "/persist";
          persistConfigs = config.environment.persistence or { };
          usesPersist =
            builtins.hasAttr persistPath persistConfigs
            && (persistConfigs.${persistPath}.enable or true);
        in
        {
          imports = [
            ((outputs.overlays.impermanence-module pkgs pkgs).impermanenceNixosModule args)
          ];

          config = lib.mkIf usesPersist {
            environment.systemPackages = with pkgs; [
              age
              ssh-to-age
            ];
          };
        };
      default = import ./nixos/impermanence;
    };
    laptop = {
      autorandr-default = import ./nixos/laptop/autorandr-default.nix;
      default = import ./nixos/laptop;
      dock = import ./nixos/laptop/dock.nix;
      intel-workstation = import ./nixos/laptop/intel-workstation.nix;
      monitor-layouts = import ./nixos/laptop/monitor-layouts.nix;
      power = import ./nixos/laptop/power.nix;
      xlayoutdisplay-hotplug = import ./nixos/laptop/xlayoutdisplay-hotplug.nix;
    };
    vm-host = {
      nixos-shell = import ./nixos/vm-host/nixos-shell;
    };
    nixos-shell-host = {
      common = import ./nixos/nixos-shell-host/common.nix;
    };
    workstation = {
      android = import ./nixos/workstation/android.nix;
      android-emulator = import ./nixos/workstation/android-emulator.nix;
      full = import ./nixos/workstation/full.nix;
      pentesting = import ./nixos/workstation/pentesting.nix;
    };
  };

  home-manager = {
    mail = {
      aerc = import ./home-manager/mail/aerc.nix;
      geary = import ./home-manager/mail/geary.nix;
    };
    desktop = {
      window-manager = import ./home-manager/desktop/window-manager.nix;
      i3 = import ./home-manager/desktop-i3/base.nix;
      legcord = import ./home-manager/desktop/legcord.nix;
      thunderbird = import ./home-manager/desktop/thunderbird.nix;
    };
    desktop-i3 = import ./home-manager/desktop-i3;
    desktop-sway = import ./home-manager/desktop-sway;
  };
}
