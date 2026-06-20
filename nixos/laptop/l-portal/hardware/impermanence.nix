{ profiles, ... }:

{
  imports = [
    profiles.nixos.impermanence.default
  ];

  local.impermanence = {
    enable = true;
    rootMapperName = "root";
    persistSshHostKeys = false;
    colordMode = "0755";

    extraSystemDirectories = [
      "/etc/nebula"
    ];
  };
}
