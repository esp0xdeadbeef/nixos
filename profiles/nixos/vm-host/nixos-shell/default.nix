{ config, lib, pkgs, ... }:

{
  options.local.vmHost.nixosShell.autoStart = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether nixos-shell VMs should start from their generated systemd timers.";
  };

  config = {
    environment.systemPackages = [
      pkgs.tmux
      pkgs.qemu
      pkgs.socat
    ];
  };
}
