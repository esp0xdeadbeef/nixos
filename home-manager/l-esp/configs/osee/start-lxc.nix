{ config
, pkgs
, lib
, systemHostName
, containerBindMounts
, ...
}:

let
  containerName = "lxc-osee";

  # The share is declared on the NixOS side (nixos/laptop/l-esp/optional/osee/
  # lxc-osee/bind-to-lxc.nix) and handed to home-manager as an argument, so the
  # bindfs argv built here is byte-identical to the argv the generated sudoers
  # NOPASSWD rule authorises. Fetching it from the real list also fails loudly
  # if the declaration is ever dropped.
  mount =
    let
      matches = builtins.filter (m: m.container == containerName) containerBindMounts;
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else
      throw "${containerName}: expected exactly one local.containerNetwork.bindMounts entry for it, found ${toString (builtins.length matches)}";

  lxcHome = "/home/deadbeef/.local/share/lxc";

  bindfsCmd =
    "${pkgs.bindfs}/bin/bindfs"
    + " --uid-offset=${toString mount.uidOffset} --gid-offset=${toString mount.gidOffset}"
    + " ${mount.source} ${mount.target}";

  # bindfs must be mounted exactly once: the unit restarts on failure and also
  # runs on every boot, so an unconditional mount either fails with "mountpoint
  # is not empty" or stacks a second mount over the container's view.
  mountScript = pkgs.writeShellScript "${containerName}-bindfs" ''
    set -euo pipefail
    if ${pkgs.util-linux}/bin/findmnt -no TARGET --mountpoint "$BINDFS_TARGET" >/dev/null 2>&1; then
      echo "$BINDFS_TARGET is already mounted; not mounting bindfs again"
      exit 0
    fi
    # sudo crosses the LXC uid boundary; the NOPASSWD rule for this exact
    # command line is generated from local.containerNetwork.bindMounts.
    exec ${pkgs.sudo}/bin/sudo -n ${bindfsCmd}
  '';

  # The container's rootfs and config live in the user's home-relative LXC
  # path. lxc-start defaults to the system path (/var/lib/lxc) and then refuses
  # with "You lack access to /var/lib/lxc", so -P must be given explicitly.
  startScript = pkgs.writeShellScript "${containerName}-start" ''
    set -euo pipefail
    exec ${pkgs.lxc}/bin/lxc-start \
      -F \
      -n ${containerName} \
      -P ${lxcHome} \
      --logfile=/tmp/${containerName}.log \
      --logpriority=DEBUG
  '';

  attachScript = pkgs.writeShellScriptBin "${containerName}-attach" ''
    exec ${pkgs.lxc}/bin/lxc-attach \
      -n ${containerName} \
      -P ${lxcHome} \
      --clear-env -v "HOME=/root"
  '';
in
{
  # home-manager/l-esp/home.nix is shared by every host, including the router
  # guests, where neither the container nor the OSEE tree exist. Ungated, this
  # unit ran there anyway and retried bindfs/lxc-start every 10s forever.
  config = lib.mkIf (systemHostName == "l-esp") {
    home.packages = [ attachScript ];

    systemd.user.services.${containerName} = {
      Unit = {
        Description = "Mount the OSEE bindfs share and start the ${containerName} container";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };

      Service = {
        Type = "simple";
        # Unlike the old launcher, which only bindfs-mounted and never started
        # the container, this mounts and then starts it, in order.
        ExecStartPre = "${mountScript}";
        ExecStart = "${startScript}";
        # Unit-level, so they do not disturb the sudoers match on the argv.
        Environment = [
          "BINDFS_SOURCE=${mount.source}"
          "BINDFS_TARGET=${mount.target}"
        ];
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStartSec = "75s";
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
