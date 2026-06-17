{
  config,
  pkgs,
  lib,
  ...
}:

{
  services.ollama.loadModels = [
    "llama3.1:8b"
    "qwen2.5-coder:1.5b-base"
    "nomic-embed-text"
    "deepseek-r1:1.5b"
    "hf.co/PantheonUnbound/Satyr-V0.1-4B:Q4_K_M"
  ];
}
