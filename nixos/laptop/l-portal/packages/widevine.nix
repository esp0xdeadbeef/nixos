{ config
, nixpkgs
, pkgs
, nixos-aarch64-widevine
, ...
}:
{
  # nixpkgs.overlays = [ nixos-aarch64-widevine.overlays.default ];
  environment.sessionVariables = {
    MOZ_GMP_PATH = "${pkgs.widevine-cdm-lacros}/gmp-widevinecdm/system-installed";
  };
}
