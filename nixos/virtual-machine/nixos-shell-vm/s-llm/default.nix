{ relativeRepo
, lib
, config
, inputs
, modulesPath
, pkgs
, ...
}:
let
  vmRoot = builtins.dirOf __curPos.file;
in
{
  _module.args.vmRoot = vmRoot;

  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (relativeRepo.module "library/10-vms/nixos-shell-vm/l-envil-host-config-nixos-shell-vm")
    inputs.nixos-shell.nixosModules.nixos-shell
    ./gnome.nix

  ];
  environment.systemPackages = with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
    claude-code
    opencode
    qwen-code
    codex
  ];


  nixos-shell.mounts.mountHome = false;
  nixos-shell.mounts.mountNixProfile = false;

  nixos-shell.mounts.extraMounts = {
    "/mnt/current_pentest" = {
      target = "/mnt/current_pentest";
      cache = "none";
    };
  };

  virtualisation.memorySize = 4096;
  virtualisation.cores = 4;
  virtualisation.graphics = true;
  virtualisation.qemu.options = [
    "-enable-kvm"
    "-cpu host"
    "-device virtio-vga-gl"
    "-display sdl,gl=on"
  ];

  services.gnome.gnome-keyring.enable = lib.mkForce false;
}
