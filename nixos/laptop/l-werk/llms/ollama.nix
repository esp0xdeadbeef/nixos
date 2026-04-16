{ config, pkgs, inputs, ... }:

let
  pkgs-unstable = import inputs.nixpkgs-unstable {
    system = pkgs.system;
    config = config.nixpkgs.config;
  };
in
{
  services.ollama = {
    enable = true;
    package = pkgs-unstable.ollama;
    loadModels = [
      "llama3.1:8b"
      "qwen2.5-coder:1.5b-base"
      "nomic-embed-text"
      "deepseek-r1:1.5b"
      "deepseek-coder:33b"
      "dolphin-mixtral:8x7b"
      "nous-hermes2:34b"
      "wizardlm2:7b"
      "llama3.1:13b"
      "gemma4:31b"
      "gemma4:e4b"
    ];
    host = "0.0.0.0";
  };

  networking.firewall.interfaces.podman0.allowedTCPPorts = [ 11434 ];
}
