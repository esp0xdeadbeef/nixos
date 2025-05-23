{
  config,
  lib,
  pkgs,
  ...
}:

let
  users = lib.attrNames (lib.filterAttrs (name: user: user.isNormalUser) config.users.users);

  # Helper: build an absolute path for every user
  mkUserPaths =
    u:
    map (p: "/home/${u}/${p}") [
      ".vscode"
      ".config/Code"
      ".local/share/lxc"
      ".local/share/containers"
    ];

  userPrunes = lib.flatten (map mkUserPaths users);

in
{
  services.locate = {
    enable = true;
    package = pkgs.plocate;
    localuser = null;
    output = "/persist/var/cache/locatedb"; # where to write the DB :contentReference[oaicite:0]{index=0}

    prunePaths = lib.mkAfter (
      [
        "/partition-root"
        "/persist"
        "/mnt/nas"
        "/nix"
      ]
      ++ userPrunes
    );
  };
}
