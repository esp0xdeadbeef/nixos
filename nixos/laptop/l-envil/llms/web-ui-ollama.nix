{ config, pkgs, ... }:

{
  virtualisation.oci-containers.containers.open-webui = {
    image = "ghcr.io/open-webui/open-webui";
    autoStart = true;
    ports = [ "127.0.0.1:3000:8080" ];
    environment = {
      OLLAMA_BASE_URL = "http://host.containers.internal:11434";
    };
    volumes = [
      "/persist/var/lib/open-webui:/app/backend/data"
    ];

  };
  environment.persistence."/persist" = {
    directories = [
      "/var/lib/open-webui"
    ];
  };

}
