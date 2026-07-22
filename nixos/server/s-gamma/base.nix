{ lib, name, profiles, relativeRepo, ... }:

{
  imports = [
    profiles.nixos.base.common
    profiles.nixos.base.maintenance
    profiles.nixos.nixpkgs.allow-unfree
    profiles.nixos.shell.zsh-prompt

    (relativeRepo.module "modules/nixos/local-users.nix")
  ];

  networking.hostName = lib.mkForce name;

  local.shell.zshPrompt.enable = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
