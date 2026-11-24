{ relativeRepo
, profiles
, ...
}:
{
  imports = [
    profiles.nixos.nixpkgs.allow-unfree
    profiles.nixos.core
    profiles.nixos.base.system
    profiles.nixos.base.maintenance
    profiles.nixos.network.private
    profiles.nixos.shell.fish
    profiles.nixos.shell.zsh-prompt

    (relativeRepo.module "modules/nixos/cuda-cache.nix")
    (relativeRepo.module "modules/nixos/local-users.nix")
  ];
}
