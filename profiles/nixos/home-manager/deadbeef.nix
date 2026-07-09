{ config
, inputs
, name
, outPath
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
        outPath
        outputs
        profiles
        ;
      hostName = name;
      primaryUser = config.local.users.primary.resolvedName;
      primaryUserHome = config.local.users.primary.homeDirectory;
    };

    users.deadbeef = import "${outPath}/home-manager/${name}/home.nix";
  };
}
