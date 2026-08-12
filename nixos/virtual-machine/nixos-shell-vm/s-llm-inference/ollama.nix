{ pkgs, profiles, ... }:

{
  # This standard NixOS Ollama service owns the persistent model store and all
  # internet-facing pulls. It is reachable only from inside the VM.
  services.ollama = {
    package = pkgs.ollama-cuda;
    host = "127.0.0.1";
    loadModels = profiles.nixos.llm.model-sets.heavy;
    environmentVariables.OLLAMA_KEEP_ALIVE = "5m";
  };

  local.llm.ollamaSmokeTest = {
    enable = true;
    pullModel = false;
  };

  systemd.services.ollama = {
    after = [ "nvidia-persistenced.service" ];
    wants = [ "nvidia-persistenced.service" ];
  };
}
