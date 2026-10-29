{
  config,
  lib,
  pkgs,
  ...
}:

let
  # 1) Grab the original users.users set so we can compute the list of normal-user names
  allUsers = config.users.users;

  # 2) Filter out only the “isNormalUser = true” entries, then grab their names
  userNames = lib.attrNames (lib.filterAttrs (_: user: user.isNormalUser) allUsers);

  # 3) Build your userPrunes exactly as before
  mkUserPaths =
    u:
    map (p: "/home/${u}/${p}") [
      ".vscode"
      ".config/Code"
      ".local/share/lxc"
      ".local/share/containers"
    ];
  userPrunes = lib.flatten (map mkUserPaths userNames);
in
{
  ######################################################################
  # A) Instead of touching `users.users`, we let the locate module make
  #    a UNIX group called “mlocate” and then we populate that group’s
  #    member list with every normal user.
  ######################################################################
  users.groups.mlocate = {
    # If you don’t care about specifying a fixed GID, you can omit “gid = …;”
    members = userNames;
  };

  ######################################################################
  # B) Enable mlocate so that it writes its DB into /persist/var/cache/locatedb
  ######################################################################
  services.locate = {
    enable = true;
    package = pkgs.mlocate;
    output = "/persist/var/cache/locatedb";
    prunePaths = lib.mkAfter (
      [
        "/partition-root"
        "/persist"
        "/mnt/nas"
        "/nix"
        "/var/lib/flatpak"
      ]
      ++ userPrunes
    );
    interval = "hourly";
  };

  ######################################################################
  # C) Make sure `locate` actually reads the DB at /persist/var/cache/locatedb
  #    instead of defaulting to /var/cache/locatedb.
  ######################################################################
  environment.variables.LOCATE_PATH = "/persist/var/cache/locatedb";

  ######################################################################
  # D) Make a bare `sudo updatedb` write the same DB as the timer.
  #
  #    impermanence bind-mounts /persist/var/cache/locatedb onto
  #    /var/cache/locatedb, and updatedb builds its database in a temporary
  #    file and rename()s it into place.  rename(2) cannot replace a mount
  #    point, so the stock default output fails with
  #
  #      updatedb: error replacing `/var/cache/locatedb':
  #        Device or resource busy
  #
  #    The update-locatedb.service timer is unaffected because it is invoked
  #    with --output=/persist/var/cache/locatedb (what services.locate.output
  #    configures).  Wrap the command so an interactive invocation defaults to
  #    the persisted path too, and keeps working if the bind mount is absent.
  #
  #    Any user-supplied --output/-o must not be duplicated: mlocate rejects
  #    "--output specified twice" rather than letting the last one win.  So the
  #    wrapper only injects the flag when the caller did not pass one.
  ######################################################################
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "updatedb" ''
      have_output=
      for arg in "$@"; do
        case "$arg" in
          -o | -o* | --output | --output=*) have_output=1 ;;
        esac
      done

      if [ -n "''${have_output-}" ]; then
        exec ${lib.getExe' pkgs.mlocate "updatedb"} "$@"
      fi

      exec ${lib.getExe' pkgs.mlocate "updatedb"} \
        --output="''${LOCATE_PATH:-/persist/var/cache/locatedb}" "$@"
    '')
  ];
}
