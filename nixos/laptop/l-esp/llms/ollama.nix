{ profiles, ... }:
{
  services.ollama.loadModels = profiles.nixos.llm.model-sets.workstation;
}
