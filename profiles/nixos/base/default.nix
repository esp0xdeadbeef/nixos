{
  outPath,
  profiles,
  ...
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

    "${outPath}/modules/nixos/cuda-cache.nix"
    "${outPath}/modules/nixos/local-users.nix"
  ];
}
