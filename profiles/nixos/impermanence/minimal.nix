{ config
, lib
, pkgs
, profiles
, ...
}:

let
  cfg = config.profiles.impermanence.minimal;
  persistenceType = lib.types.listOf lib.types.anything;
  persistPath = lib.escapeShellArg cfg.persistPath;
in
{
  imports = [
    profiles.nixos.impermanence.module
  ];

  options.profiles.impermanence.minimal = {
    enable = lib.mkEnableOption "minimal impermanence defaults for headless hosts";

    persistPath = lib.mkOption {
      type = lib.types.str;
      default = "/persist";
      description = "Persistent root used by impermanence.";
    };

    hideMounts = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Hide bind mounts created by impermanence.";
    };

    machineId.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Persist and bootstrap /etc/machine-id.";
    };

    repairStateRootOwnership.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Repair root ownership for persistent /var state before impermanence links files.";
    };

    extraSystemDirectories = lib.mkOption {
      type = persistenceType;
      default = [ ];
      description = "Additional system directories persisted under persistPath.";
    };

    extraSystemFiles = lib.mkOption {
      type = persistenceType;
      default = [ ];
      description = "Additional system files persisted under persistPath.";
    };
  };

  config = lib.mkIf cfg.enable {
    fileSystems.${cfg.persistPath}.neededForBoot = true;
    fileSystems."/nix".neededForBoot = true;

    environment.persistence.${cfg.persistPath} = {
      enable = true;
      hideMounts = cfg.hideMounts;
      directories = [
        "/root/.ssh"
        "/var/lib/nixos"
        "/var/lib/systemd"
        "/var/log"
      ]
      ++ cfg.extraSystemDirectories;
      files = lib.optionals cfg.machineId.enable [
        "/etc/machine-id"
      ]
      ++ cfg.extraSystemFiles;
    };

    system.activationScripts.prepareImpermanenceMachineId = lib.mkIf cfg.machineId.enable {
      deps = [ "createPersistentStorageDirs" ];
      text = ''
        persist_path=${persistPath}
        install -d -m 0755 "$persist_path/etc"

        if [ -e /etc/machine-id ] && [ ! -s "$persist_path/etc/machine-id" ]; then
          install -D -m 0444 /etc/machine-id "$persist_path/etc/machine-id"
        fi

        if [ ! -s "$persist_path/etc/machine-id" ]; then
          ${pkgs.systemd}/bin/systemd-id128 new > "$persist_path/etc/machine-id"
          chmod 0444 "$persist_path/etc/machine-id"
        fi

        if ! mountpoint -q /etc/machine-id; then
          rm -f /etc/machine-id
        fi
      '';
    };

    system.activationScripts.repairPersistentStateRootOwnership = lib.mkIf cfg.repairStateRootOwnership.enable {
      deps = [ "createPersistentStorageDirs" ];
      text = ''
        persist_path=${persistPath}

        for path in "$persist_path/var" "$persist_path/var/lib" "$persist_path/var/log" /var /var/lib /var/log; do
          if [ -d "$path" ]; then
            chown root:root "$path"
            chmod 0755 "$path"
          fi
        done

        for journalRoot in "$persist_path/var/log/journal" /var/log/journal; do
          if [ -d "$journalRoot" ]; then
            chown root:systemd-journal "$journalRoot"
            chmod 2755 "$journalRoot"
          fi

          for journalDir in "$journalRoot"/*; do
            [ -d "$journalDir" ] || continue
            chown root:systemd-journal "$journalDir"
            chmod 2755 "$journalDir"
          done
        done
      '';
    };

    system.activationScripts.persist-files.deps =
      lib.optionals cfg.machineId.enable [
        "prepareImpermanenceMachineId"
      ]
      ++ lib.optionals cfg.repairStateRootOwnership.enable [
        "repairPersistentStateRootOwnership"
      ];
  };
}
