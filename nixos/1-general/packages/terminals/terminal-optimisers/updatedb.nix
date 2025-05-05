{ config, lib, pkgs, ... }:

let
  users = builtins.attrNames config.users.users;

  # Helper: build an absolute path for every user
  mkUserPaths = u: map (p: "/home/${u}/${p}") [
    ".vscode"
    ".config/Code"
    ".local/share/lxc"
    ".local/share/containers"
  ];

  userPrunes = lib.flatten (map mkUserPaths users);

in
{
  services.locate = {
    enable    = true;
    package   = pkgs.plocate;
    localuser = null;

    prunePaths = lib.mkAfter (
      [ "/partition-root" "/persist" ] ++ userPrunes
    );
  };
}
