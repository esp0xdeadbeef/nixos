{ pkgs, ... }:
let
  unstablePkgs = pkgs.unstable;
in
{
  programs.vscode = {
    enable = true;
    package = unstablePkgs.vscode;
    mutableExtensionsDir = true;
  };

  programs.vscodium = {
    enable = true;
    package = unstablePkgs.vscodium.fhs;
    mutableExtensionsDir = true;
  };
}
