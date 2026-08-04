{ profiles, ... }:
{
  imports = [
    profiles.nixos.llm.ollama-base
    profiles.nixos.llm-clients.claude-deepseek
    ./ollama.nix
  ];
}
