{ lib, lanzaboote, impermanence, home-manager, nixpkgs }:

system: hostname: hardwareModules: extraModules: secureBoot: isEphemeral:

nixpkgs.lib.nixosSystem {
  inherit system;

  specialArgs = {
    inherit nixpkgs hostname;
    username = "deadbeef";
  };

  modules =
    lib.filter (m: m != null) [
      ../hosts/desktop/users-and-groups.nix
      ../hosts/system/version.nix
      ../hosts/system/autoupdate.nix
      ../hosts/time/timezone.nix
      ../hosts/general/tooling.nix
      home-manager.nixosModules.home-manager
      impermanence.nixosModules.impermanence
      {
        services.fwupd.enable = true;
        nixpkgs.config.allowUnfree = true;
      }
      (if secureBoot then lanzaboote.nixosModules.lanzaboote else null)
    ]
    ++ hardwareModules
    ++ lib.optional isEphemeral ../hosts/modules/impermanence.nix
    ++ extraModules;
}
