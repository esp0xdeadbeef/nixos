{
  outPath,
  profiles,
  ...
}:
{
  imports = [
    profiles.nixos.nixpkgs.allow-unfree
    profiles.nixos.base.common
    profiles.nixos.base.system
    profiles.nixos.base.maintenance

    "${outPath}/modules/nixos/cuda-cache.nix"
    "${outPath}/modules/nixos/local-users.nix"
  ];
}
