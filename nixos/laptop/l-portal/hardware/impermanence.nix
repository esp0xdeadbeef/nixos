{ profiles, ... }:

{
  imports = [
    profiles.nixos.impermanence.default
  ];

  local.impermanence = {
    enable = true;
    rootMapperName = "root";
    colordMode = "0755";

  };
}
