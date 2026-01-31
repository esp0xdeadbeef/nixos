{ config, pkgs, ... }:
{
  services.ollama = {
    enable = true;
    loadModels = [
      "llama3.1:8b"
      "qwen2.5-coder:1.5b-base"
      "nomic-embed-text"
      "deepseek-r1:1.5b"
    ];
  };
}
