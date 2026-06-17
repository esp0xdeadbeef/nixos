{ profiles, ... }:
{
  imports = [
    profiles.nixos.llm.lmstudio
    profiles.nixos.llm.ollama-base
    ./ollama.nix
  ];
}
