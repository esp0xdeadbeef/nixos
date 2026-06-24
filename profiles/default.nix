{
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
    };
    shell = {
      fish = import ./nixos/shell/fish.nix;
      zsh-prompt = import ./nixos/shell/zsh-prompt.nix;
    };
    ssh = {
      deadbeef-authorized-keys = import ./nixos/ssh/deadbeef-authorized-keys.nix;
    };
    network = {
      private = import ./nixos/network/private.nix;
      workstation = import ./nixos/network/workstation.nix;
    };
    virtualization = {
      docker = import ./nixos/virtualization/docker.nix;
      host = import ./nixos/virtualization/host.nix;
      libvirt = import ./nixos/virtualization/libvirt.nix;
      lxc = import ./nixos/virtualization/lxc.nix;
      podman = import ./nixos/virtualization/podman.nix;
    };
    llm-clients = {
      agents = import ./nixos/llm-clients/agents.nix;
    };
    llm = {
      lmstudio = import ./nixos/llm/lmstudio.nix;
      ollama-base = import ./nixos/llm/ollama-base.nix;
      open-webui = import ./nixos/llm/open-webui.nix;
    };
    impermanence = {
      default = import ./nixos/impermanence;
    };
    laptop = {
      autorandr-default = import ./nixos/laptop/autorandr-default.nix;
      default = import ./nixos/laptop;
      desktop-apps = import ./nixos/laptop/desktop-apps.nix;
      dock = import ./nixos/laptop/dock.nix;
      power = import ./nixos/laptop/power.nix;
      xlayoutdisplay-hotplug = import ./nixos/laptop/xlayoutdisplay-hotplug.nix;
    };
    vm-host = {
      nixos-shell = import ./nixos/vm-host/nixos-shell;
    };
    workstation = {
      android = import ./nixos/workstation/android.nix;
      android-emulator = import ./nixos/workstation/android-emulator.nix;
      full = import ./nixos/workstation/full.nix;
      pentesting = import ./nixos/workstation/pentesting.nix;
    };
  };

  home-manager = {
    desktop = {
      window-manager = import ./home-manager/desktop/window-manager.nix;
      legcord = import ./home-manager/desktop/legcord.nix;
    };
    desktop-i3 = import ./home-manager/desktop-i3;
    desktop-sway = import ./home-manager/desktop-sway;
  };
}
