{
  lib,
  lanzaboote,
  impermanence,
  home-manager,
  nixpkgs,
}:

system: hostname: hardwareModules: extraModules: secureBoot: isEphemeral:

nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = {
    inherit nixpkgs hostname;
    username = "deadbeef";
  };
  modules =
    lib.filter (module: module != null) [
      ./desktop/users-and-groups.nix
      ./system/version.nix
      ./system/autoupdate.nix
      ./time/timezone.nix
      ./general/tooling.nix
      home-manager.nixosModules.home-manager
      impermanence.nixosModules.impermanence

      {
        services.fwupd.enable = true;
        nixpkgs.config.allowUnfree = true;
      }

      (if secureBoot then lanzaboote.nixosModules.lanzaboote else null)
    ]
    ++ hardwareModules
    ++ lib.optional isEphemeral ./modules/impermanence.nix
    ++ extraModules;
}
