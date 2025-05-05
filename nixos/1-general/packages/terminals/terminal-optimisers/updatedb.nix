{
  config,
  lib,
  pkgs,
  ...
}:

let
  users = builtins.attrNames config.users.users;

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
    output = "/persist/var/cache/locatedb"; # this is broken, but ill keep it in it, might be working someday
    interval = "hourly";

    prunePaths = lib.mkAfter (
      [
        "/tmp"
        "/var/tmp"
        "/var/cache"
        "/var/lock"
        "/var/run"
        "/var/spool"
        "/nix/store"
        "/nix/var/log/nix"
        "/partition-root"
        "/persist"
      ]
      ++ userPrunes
    );
  };
}
