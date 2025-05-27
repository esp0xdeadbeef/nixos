{ config, pkgs, ... }:
{

  # need to move this to docker.nix:
  virtualisation.docker.enable = true;

  # boot.binfmt.emulatedSystems = [
  #   "aarch64-linux"
  #   "riscv64-linux"
  # ];
}
