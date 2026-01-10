{ config, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [
    25565
    25566
  ];

  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    dockerCompat = false;
  };

  virtualisation.oci-containers.backend = "podman";

  virtualisation.oci-containers.containers.minecraft-prod = {
    image = "itzg/minecraft-server";
    autoStart = true;

    environment = {
      VERSION = "1.21.11";
      EULA = "TRUE";
      TYPE = "SPIGOT";
      MEMORY = "4G";
      ENABLE_ROLLING_LOGS = "true";
    };

    ports = [
      "25565:25565"
    ];

    volumes = [
      "/persist/minecraft/prod:/data"
    ];

    extraOptions = [
      "--name=minecraft-prod"
    ];
  };

  #############################################
  # Minecraft – TEST (IPv6-only mirror)
  #############################################

  virtualisation.oci-containers.containers.minecraft-test = {
    image = "itzg/minecraft-server";
    autoStart = true;

    environment = {
      VERSION = "1.21.11";
      EULA = "TRUE";
      TYPE = "SPIGOT";
      MEMORY = "4G";
      ONLINE_MODE = "false"; # useful for testing
    };

    # IPv6-only bind
    ports = [
      "[::]:25566:25565"
    ];

    volumes = [
      "/persist/minecraft/test:/data"
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

    script = ''
      set -euo pipefail

      SRC="/persist/minecraft/prod/world/"
      DST="/persist/minecraft/test/world/"

      mkdir -p "$DST"

      echo "[$(date -Is)] Starting Minecraft world sync"

      # Stop test server to avoid corruption
      ${pkgs.podman}/bin/podman stop minecraft-test || true

      ${pkgs.rsync}/bin/rsync -a \
        --delete \
        --numeric-ids \
        --inplace \
        "$SRC" "$DST"

      ${pkgs.podman}/bin/podman start minecraft-test

      echo "[$(date -Is)] Sync complete"
    '';
  };

  systemd.timers.minecraft-world-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*/4:00";
      Persistent = true;
    };
  };

  #############################################
  # Ensure directories exist (idempotent)
  #############################################

  systemd.tmpfiles.rules = [
    "d /persist/minecraft 0755 root root -"
    "d /persist/minecraft/prod 0755 root root -"
    "d /persist/minecraft/prod/world 0755 root root -"
    "d /persist/minecraft/test 0755 root root -"
    "d /persist/minecraft/test/world 0755 root root -"
  ];
}
