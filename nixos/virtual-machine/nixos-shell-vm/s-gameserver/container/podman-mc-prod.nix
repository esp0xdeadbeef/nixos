{ config, pkgs, ... }:

{
  systemd.services."minecraft-prod" = {
    unitConfig = {
      StartLimitIntervalSec = 0;
    };

    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
    };
  };
  virtualisation.oci-containers.containers.minecraft-prod = {
    image = "docker.io/itzg/minecraft-server";
    autoStart = true;

    environment = {
      VERSION = "1.21.11";
      EULA = "TRUE";
      TYPE = "SPIGOT";
      MEMORY = "8G";
      ENABLE_ROLLING_LOGS = "true";
    };

    ports = [
      "25565:25565"
    ];

    volumes = [
      "/persist/game-servers/minecraft/prod:/data"
    ];

    extraOptions = [
      "--name=minecraft-prod"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /persist/game-servers/minecraft/prod 0755 root root -"
  ];

}
