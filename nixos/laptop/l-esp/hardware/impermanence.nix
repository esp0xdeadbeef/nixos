{ profiles, ... }:

{
  imports = [
    profiles.nixos.impermanence.default
  ];

  local.impermanence = {
    enable = true;
    rootMapperName = "crypted";

    extraUserDirectories = [
      ".android"
    ];

    extraUserFiles = [
      ".xlayoutdisplay"
    ];
  };
}
