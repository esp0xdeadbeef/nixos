{ profiles, ... }:

{
  imports = [
    profiles.nixos.impermanence.default
  ];

  local.impermanence = {
    enable = true;
    rootMapperName = "crypted";

    extraSystemDirectories = [
      "/etc/nebula"
      {
        directory = "/var/cache/ccache";
        user = "root";
        group = "nixbld";
        mode = "2770";
      }
    ];
  };
}
