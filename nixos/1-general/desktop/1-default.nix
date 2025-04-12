{ config, pkgs, ... }: {
  imports = [
    ./applets.nix
    ./darkmode.nix
    ./environment.nix
    ./fonts.nix
    ./packages.nix
    ./shell-env.nix
    ./users-and-groups.nix
  ];

}