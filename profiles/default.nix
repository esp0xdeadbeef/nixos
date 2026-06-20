{
  nixos = {
    base = import ./nixos/base;
    boot = {
      usb-removable = import ./nixos/boot/usb-removable.nix;
    };
    desktop = {
      common = import ./nixos/desktop/common.nix;
      i3 = import ./nixos/desktop/i3.nix;
    };
    packages = {
      workstation = import ./nixos/packages/workstation.nix;
    };
    virtualization = {
      host = import ./nixos/virtualization/host.nix;
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
