{ profiles, ... }:

{
  imports = [
    profiles.nixos.impermanence.default
  ];

  local.impermanence = {
    enable = true;
    rootMapperName = "crypted";

    extraUserFiles = [
      ".xlayoutdisplay"
    ];
  };
}
