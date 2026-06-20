{ pkgs, ... }:
{
  services.ollama = {
    enable = true;
    package = pkgs.unstable.ollama-cuda;
    #acceleration = "cuda";

    loadModels = [
      "llama3.1:8b"
      "qwen2.5-coder:1.5b-base"
      "nomic-embed-text"
      "deepseek-r1:1.5b"
      "deepseek-coder:33b"
      "dolphin-mixtral:8x7b"
      "nous-hermes2:34b"
      "wizardlm2:7b"
      "mistral"
      "gemma4:31b"
      "gemma4:e4b"
    ];

    host = "0.0.0.0";
  };

  networking.firewall.interfaces.podman0.allowedTCPPorts = [ 11434 ];
}
