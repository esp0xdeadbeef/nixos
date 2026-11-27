{ config
, inputs
, lib
, name
, relativeRepo
, outputs
, profiles
, ...
}:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  # The home-manager config directory to use, and the host identity its
  # per-host modules resolve against. Defaults to this host's directory name.
  #
  # A variant host that is the *same machine* (same keys, same secrets, same
  # user config) but a different flake attribute -- e.g. l-portal-unstable,
  # which rebuilds l-portal against a different nixos-hardware -- sets this to
  # the original host so it reuses that host's home configuration instead of
  # needing a duplicate tree.
  options.local.homeManager.hostName = lib.mkOption {
    type = lib.types.str;
    default = name;
    defaultText = lib.literalExpression "the host's directory name";
    description = ''
      Name of the directory under home-manager/ whose home.nix is imported,
      and the `hostName` passed to home-manager modules.
    '';
  };

  config.home-manager = {
    backupFileExtension = "hm-backup";

    sharedModules = [
      inputs.sops-nix.homeManagerModules.sops
    ];

    extraSpecialArgs = {
      inherit
        inputs
        relativeRepo
        outputs
        profiles
        ;
      hostName = config.local.homeManager.hostName;
      # The system identity the home modules gate on (e.g. "l-esp").
      systemHostName = config.networking.hostName;
      # The single source of truth for bindfs container shares. The NixOS side
      # generates the sudoers rule and the shutdown teardown from this list; the
      # home-manager unit derives the argv it runs from the same values.
      containerBindMounts = config.local.containerNetwork.bindMounts;
      # The setuid sudo wrapper (`/run/wrappers/bin/sudo`). The bindfs unit runs
      # sudo from home-manager, which has no access to the system's sudo options;
      # it must be handed the wrapper path, never `pkgs.sudo`: that store binary
      # is not setuid root and aborts with "must be owned by uid 0 and have the
      # setuid bit set". `/run/current-system/sw/bin/sudo` is the same trap -- it
      # is only a symlink to the unsetuid store binary.
      sudoCommand = "${config.security.wrapperDir}/sudo";
      primaryUser = config.local.users.primary.resolvedName;
      primaryUserHome = config.local.users.primary.homeDirectory;
    };

    users.deadbeef = import (relativeRepo.module "home-manager/${config.local.homeManager.hostName}/home.nix");
  };
}
