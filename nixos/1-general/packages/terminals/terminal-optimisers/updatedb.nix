{
  config,
  lib,
  pkgs,
  ...
}:

let
  users = builtins.attrNames config.users.users;

  mkUserPaths =
    u:
    map (p: "/home/${u}/${p}") [
      ".vscode"
      ".config/Code"
      ".local/share/lxc"
      ".local/share/containers"
      ".cache"
    ];

  userPrunes = lib.flatten (map mkUserPaths users);

  prunePaths = [
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
    "/run/systemd"
    "/sys"
    "/run"
  ] ++ userPrunes;

  # Prune paths string for updatedb
  pruneString = lib.concatStringsSep " " prunePaths;

  # Wrapped updatedb to enforce output path
  wrappedUpdatedb = pkgs.writeShellScriptBin "updatedb" ''
    exec ${pkgs.mlocate}/bin/updatedb \
      --output=/persist/var/cache/locatedb \
      --prunepaths="${pruneString}" \
      --prune-bind-mounts=yes \
      --require-visibility=no "$@"
  '';

  # Optional: wrap locate to use same DB
  wrappedLocate = pkgs.writeShellScriptBin "locate" ''
    exec ${pkgs.mlocate}/bin/locate -d /persist/var/cache/locatedb "$@"
  '';
in
{
  environment.systemPackages = [
    wrappedUpdatedb
    wrappedLocate
    pkgs.mlocate
  ];

  # Make sure target path exists and is writable
  systemd.tmpfiles.rules = [
    "d /persist/var/cache 0755 root root -"
    "f /persist/var/cache/locatedb 0644 nobody nobody -"
  ];

  systemd.services.updatedb = {
    description = "Update mlocate database";
    path = [ wrappedUpdatedb ];
    script = "updatedb";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };

  systemd.timers.updatedb = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "1h";
      Persistent = true;
    };
  };
}
