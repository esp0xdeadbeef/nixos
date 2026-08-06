{ profiles, relativeRepo, ... }:
{
  imports = [
    profiles.nixos.llm.ollama-base
    profiles.nixos.llm-clients.agents-all
    ./ollama.nix
  ];

  sops.secrets."deepseek-api".sopsFile = relativeRepo.sourcePath "secrets/l-esp-default-deadbeef.yaml";
}
