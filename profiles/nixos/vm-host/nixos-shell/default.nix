{ pkgs, ... }:

{
  environment.systemPackages = [
    pkgs.tmux
    pkgs.qemu
    pkgs.socat
  ];
}
