{ pkgs, nixpkgs-unstable, ... }: {
  nixpkgs.config.allowUnfree = true;

  nixpkgs.overlays = [
    (final: prev: {
      burpsuite = nixpkgs-unstable.legacyPackages.${prev.system}.burpsuite;
    })
  ];

  environment.systemPackages = with pkgs; [
    #burpsuite
    (burpsuite.override { proEdition = true; })
  ];
}

