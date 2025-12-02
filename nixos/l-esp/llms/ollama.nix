{
  config,
  pkgs,
  lib,
  ...
}:

# Use bindfs to overlay persistent storage into Ollama's dynamic directory
{
  # Ensure bindfs is available
  # environment.systemPackages = with pkgs; [ bindfs ];

  # # Activation script to bindfs mount before system starts services
  # system.activationScripts.bindOllama = ''
  #   mkdir -p /var/lib/private/ollama 
  #   mkdir -p /persist/var/lib/ollama /persist/var/lib/ollama/models /var/lib/private/ollama/.ollama/models
  #   "${pkgs.bindfs}/bin/bindfs" /persist/var/lib/ollama /var/lib/private/ollama
  #   "${pkgs.bindfs}/bin/bindfs" /persist/var/lib/ollama/models /var/lib/private/ollama/.ollama/models

  # ''; 

  # # Configure the Ollama systemd service
  # systemd.services.ollama = {
  #   enable = true;
  #   serviceConfig = {
  #     DynamicUser = true; # use dynamic user
  #     PermissionsStartOnly = true; # allow preStart hooks to run as root
  #   };
  #   # environment.OLLAMA_MODELS = "/persist/var/lib/ollama/models"; # default models path
  # };

  # Enable Ollama daemon and preload models
  services.ollama = {
    enable = true;
    loadModels = [
      "llama3.1:8b"
      "qwen2.5-coder:1.5b-base"
      "nomic-embed-text"
      "deepseek-r1:1.5b"
      "satyr-v0.1-4b"
    ];
  };
}
