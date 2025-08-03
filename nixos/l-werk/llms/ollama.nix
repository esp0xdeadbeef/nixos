{ config, pkgs, ... }:
{
  services.ollama = {
    enable = true;
    acceleration = "cuda";
    loadModels = [
      "llama3.2:8b"
      "deepseek-r1:1.5b"
    ];
  };
}
