{ config
, inputs
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

  home-manager = {
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
      hostName = name;
      primaryUser = config.local.users.primary.resolvedName;
      primaryUserHome = config.local.users.primary.homeDirectory;
    };

    users.deadbeef = import (relativeRepo.module "home-manager/${name}/home.nix");
  };
}
