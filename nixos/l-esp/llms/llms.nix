{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
        unstablePkgs  = import inputs.nixpkgs-unstable { config.allowUnfree = true; };
  in {


  # overlay unstable's ollama into the main pkgs
  nixpkgs.overlays = [
    (final: prev: {
      ollama = unstablePkgs.ollama;
    })
  ];
users.users.ollama = { isSystemUser = true; group = "ollama"; home = "/var/lib/ollama"; };
  users.groups.ollama = {};

  services.ollama = {
    enable       = true;
    # acceleration = "rocm";
    loadModels   = [ "llama3.1:8b" "qwen2.5-coder:1.5b-base" "nomic-embed-text:latest" ];
    home = "/persist/var/lib/ollama";   # anything *outside* /var/lib works
  };

  # impermanence stays exactly the same
  # environment.persistence."/persist".directories = [ "/var/lib/ollama" ];

  # override the one flag that breaks things
  systemd.services.ollama.serviceConfig.DynamicUser = lib.mkForce false;


  ## Only the bits that MUST be writable; keep the rest of the sandbox:
  # systemd.services.ollama.serviceConfig = {
  #   User             = "ollama";
  #   Group            = "ollama";
  #   StateDirectory   = "ollama";   # systemd auto-creates & chowns
  #   RuntimeDirectory = "ollama";
  #   ProtectSystem    = "strict";   # everything else read-only
  #   ReadWritePaths   = [ "/var/lib/ollama" ];
  # };

  #### 4. optional CLI ########################################################
  environment.systemPackages = [ pkgs.ollama ];

}
