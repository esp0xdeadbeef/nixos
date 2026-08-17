{ profiles, ... }:

{
  imports = [
    profiles.nixos.impermanence.default
  ];

  local.impermanence = {
    enable = true;
    rootMapperName = "crypted";

    extraSystemDirectories = [
      "/var/lib/waydroid/"
      "/var/lib/tang"
    ];
  };
}
