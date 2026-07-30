{ profiles, ... }:
{
  imports = [
    profiles.nixos.llm.ollama-base
    ./claude.nix
    ./ollama.nix
  ];
}
