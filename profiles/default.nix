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
      usb-removable = import ./nixos/boot/usb-removable.nix;
    };
    desktop = {
      common = import ./nixos/desktop/common.nix;
      gnome = import ./nixos/desktop/gnome.nix;
      i3 = import ./nixos/desktop/i3.nix;
      sway = import ./nixos/desktop/sway.nix;
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
      zsh-prompt = import ./nixos/shell/zsh-prompt.nix;
    };
    network = {
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
      default = import ./nixos/laptop;
      dock = import ./nixos/laptop/dock.nix;
      power = import ./nixos/laptop/power.nix;
    };
    vm-host = {
      nixos-shell = import ./nixos/vm-host/nixos-shell;
    };
    workstation = {
      full = import ./nixos/workstation/full.nix;
      pentest-cleanup = import ./nixos/workstation/pentest-cleanup.nix;
    };
  };

  home-manager = {
    desktop-i3 = import ./home-manager/desktop-i3;
  };
}
