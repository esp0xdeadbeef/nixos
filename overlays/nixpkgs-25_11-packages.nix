{ inputs }: final: _prev: {
  nixpkgs-25_11 = import inputs.nixpkgs-25_11 {
    system = final.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
}
