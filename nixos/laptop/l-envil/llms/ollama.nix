{ pkgs, profiles, ... }:
{
  services.ollama = {
    enable = true;
    package = pkgs.unstable.ollama-cuda;
    #acceleration = "cuda";

    loadModels = profiles.nixos.llm.model-sets.heavy;

    host = "0.0.0.0";
  };

  networking.firewall.interfaces.podman0.allowedTCPPorts = [ 11434 ];
}
