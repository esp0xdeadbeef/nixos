{ config
, inputs
, lib
, pkgs
, ...
}:

let
  registry = import ./registry.nix {
    inherit inputs lib pkgs;
  };

  cfg = config.local.llmClients.agents;

  selectedPackageNames = lib.unique cfg.packageNames;
  hasRunnablePackage = name: registry.runnablePackages ? ${name};
  hasPersistenceMetadata = name: registry.persistenceByPackageName ? ${name};

  validSelectedPackageNames = lib.filter hasRunnablePackage selectedPackageNames;
  selectedPackages = map (name: registry.runnablePackages.${name}) validSelectedPackageNames;

  selectedPackageNamesWithPersistence = lib.filter hasPersistenceMetadata validSelectedPackageNames;
  selectedPersistence = lib.genAttrs selectedPackageNamesWithPersistence (
    name: registry.persistenceByPackageName.${name}
  );

  # Repo-managed Pi extensions, installed into every home-manager user's
  # ~/.pi/agent/extensions so they survive impermanence root rotation. They are
  # declarative files, not persisted state: the persist-store copy is a mount
  # under ~/.pi and would otherwise be the only copy.
  piSelected = lib.elem "pi" selectedPackageNames;
  piExtensionFiles = lib.optionalAttrs piSelected (
    lib.mapAttrs
      (name: _: ../llm-clients/pi-extensions/${name})
      (lib.filterAttrs (_name: type: type == "regular") (builtins.readDir ../llm-clients/pi-extensions))
  );
in
{
  imports = [ ./cache.nix ];

  options.local.llmClients.agents = {
    packageNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = registry.defaultPackageNames;
      example = [
        "codex"
        "hermes-agent"
        "claude-code"
        "qwen-code"
      ];
      description = ''
        Runnable package names selected from inputs.llm-agents.packages for this host.
      '';
    };

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = selectedPackages;
      readOnly = true;
      description = "Package derivations selected by local.llmClients.agents.packageNames.";
    };

    persistence = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          directories = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Home-relative directories persisted for this agent.";
          };

          files = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Home-relative files persisted for this agent.";
          };
        };
      });
      default = selectedPersistence;
      readOnly = true;
      description = "Persistence metadata for the selected LLM agent packages.";
    };

    persistenceDirectories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = lib.unique (
        lib.concatMap
          (
            name: registry.persistenceByPackageName.${name}.directories or [ ]
          )
          selectedPackageNamesWithPersistence
      );
      readOnly = true;
      description = "Home-relative directories persisted for all selected LLM agents.";
    };

    persistenceFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = lib.unique (
        lib.concatMap
          (
            name: registry.persistenceByPackageName.${name}.files or [ ]
          )
          selectedPackageNamesWithPersistence
      );
      readOnly = true;
      description = "Home-relative files persisted for all selected LLM agents.";
    };

    runnablePackageNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = registry.runnablePackageNames;
      readOnly = true;
      description = "Runnable package names exposed by the llm-agents input for this system.";
    };

    piExtensions = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = piExtensionFiles;
      readOnly = true;
      description = ''
        Repo-managed Pi extensions (files under profiles/nixos/llm-clients/
        pi-extensions) installed into each home-manager user's
        ~/.pi/agent/extensions. Empty unless `pi` is a selected package.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = (lib.subtractLists registry.runnablePackageNames selectedPackageNames) == [ ];
        message = ''
          local.llmClients.agents.packageNames contains packages that are not runnable llm-agents outputs for ${pkgs.stdenv.hostPlatform.system}: ${
            lib.concatStringsSep ", " (lib.subtractLists registry.runnablePackageNames selectedPackageNames)
          }
        '';
      }
      {
        assertion = (lib.subtractLists (lib.attrNames registry.persistenceByPackageName) validSelectedPackageNames) == [ ];
        message = ''
          local.llmClients.agents.packageNames contains packages without explicit persistence metadata: ${
            lib.concatStringsSep ", " (lib.subtractLists (lib.attrNames registry.persistenceByPackageName) validSelectedPackageNames)
          }
        '';
      }
    ];

    environment.systemPackages = cfg.packages ++ [
      pkgs.psmisc
      pkgs.bubblewrap
    ];

    # Install the repo-managed Pi extensions into every home-manager user via
    # sharedModules: that applies to all users without naming any of them, so
    # the module never reads config.home-manager.users (which would recurse,
    # since this is itself a definition of it). home.file links point into the
    # flake store, so they stay immutable and survive root rotation.
    home-manager.sharedModules = lib.mkIf (cfg.piExtensions != { }) [
      {
        home.file = lib.mapAttrs'
          (
            fileName: src:
              lib.nameValuePair ".pi/agent/extensions/${fileName}" { source = src; }
          )
          cfg.piExtensions;
      }
    ];
  };
}
