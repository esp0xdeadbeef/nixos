{ profiles, ... }:
{
  imports = [
    profiles.nixos.llm.ollama-base
    ./ollama.nix
  ];
}
