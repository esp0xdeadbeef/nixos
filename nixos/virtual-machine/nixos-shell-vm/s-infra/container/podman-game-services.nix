{ config, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [
    25565
    25566
  ];

  networking.firewall.allowedUDPPortRanges = [
    {
      from = 2456;
      to = 2458;
    }
  ];

  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    dockerCompat = false;
  };

  virtualisation.oci-containers.backend = "podman";

  virtualisation.oci-containers.containers.valheim-server = {
    image = "docker.io/lloesche/valheim-server";
    autoStart = true;

    environment = {
      SERVER_NAME = "test-server";
      SERVER_PASS = "abc2222";
      WORLD_NAME = "test-world";
      SERVER_PUBLIC = "true";
    };

    ports = [
      "2456-2458:2456-2458/udp"
    ];

    volumes = [
      "/persist/game-servers/valheim/prod:/config"
    ];

    extraOptions = [
      "--name=valheim-server"
    ];
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

  virtualisation.oci-containers.containers.minecraft-test = {
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
      "25566:25565"
    ];

    volumes = [
      "/persist/game-servers/minecraft/test:/data"
    ];

    extraOptions = [
      "--name=minecraft-test"
    ];
  };

  #############################################
  # World sync: prod → test (every 4 hours)
  #############################################

  systemd.services.minecraft-world-sync = {
    description = "Sync Minecraft world from prod to test";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    path = [
      pkgs.systemd
      pkgs.rsync
    ];

    script = ''
      set -euo pipefail

      SRC="/persist/game-servers/minecraft/prod/"
      DST="/persist/game-servers/minecraft/test/"

      echo "[$(date -Is)] Stopping test server"
      systemctl stop podman-minecraft-test.service

      echo "[$(date -Is)] Syncing world data"
      rsync -a \
        --delete \
        --numeric-ids \
        --inplace \
        "$SRC" "$DST"

      echo "[$(date -Is)] Starting test server"
      systemctl start podman-minecraft-test.service

      echo "[$(date -Is)] Sync complete"
    '';
  };

  systemd.timers.minecraft-world-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {

      OnCalendar = "*-*-* 04:00:00";
      Persistent = true;
    };
  };

  systemd.services.minecraft-world-test-message = {
    description = "Test message service to the test-server with rcon-cli.";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    path = [ pkgs.podman ];

    script = ''
      podman exec minecraft-test rcon-cli say '!!!Test server!!!'
    '';
  };
  systemd.timers.minecraft-world-test-message = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "minutely";
      Persistent = true;
      AccuracySec = "1s";
    };
  };

  #############################################
  # Ensure directories exist (idempotent)
  #############################################

  systemd.tmpfiles.rules = [
    "d /persist/game-servers/minecraft/prod 0755 root root -"
    "d /persist/game-servers/minecraft/test 0755 root root -"
    "d /persist/game-servers/valheim/prod 0755 root root -"
  ];
}
