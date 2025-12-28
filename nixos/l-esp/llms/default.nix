{ pkgs, ... }:
{
  imports = [
    ./lmstudio.nix
    ./ollama.nix
  ];
}
