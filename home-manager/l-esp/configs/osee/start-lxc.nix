{ pkgs
, lib
, systemHostName
, containerBindMounts
, sudoCommand
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

  # How long the container's init gets to shut down before lxc-stop hard-kills
  # it. ExecStop below passes this to `lxc-stop -t`, and `TimeoutStopSec` is set
  # above it so systemd waits for lxc-stop to finish rather than killing it.
  shutdownTimeoutSec = 45;
  stopTimeoutSec = shutdownTimeoutSec + 20;

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
    #
    # Use the setuid wrapper, never pkgs.sudo: the raw store binary is not
    # setuid root, so it aborts with "must be owned by uid 0 and have the
    # setuid bit set". That failed every boot, lxc-osee.service restarted
    # forever, the container never came up and the x2go session gate then had
    # no eth0 address to wait for.
    exec ${sudoCommand} -n ${bindfsCmd}
  '';

  # The container's rootfs and config live in the user's home-relative LXC
  # path. lxc-start defaults to the system path (/var/lib/lxc) and then refuses
  # with "You lack access to /var/lib/lxc", so -P must be given explicitly.
  #
  # -F keeps lxc-start in the foreground, which is what pins the container to
  # this unit's cgroup; without it systemd could not track it.
  startScript = pkgs.writeShellScript "${containerName}-start" ''
    set -euo pipefail
    exec ${pkgs.lxc}/bin/lxc-start \
      -F \
      -n ${containerName} \
      -P ${lxcHome} \
      --logfile=/tmp/${containerName}.log \
      --logpriority=DEBUG
  '';

  # Stop the container gracefully instead of letting systemd SIGTERM
  # `lxc-start -F` and then SIGKILL it.
  #
  # `lxc-start -F` does not initiate a container shutdown on SIGTERM: the
  # signal goes to lxc-start, not to the container's init, so the unit sat in
  # `stop-sigterm` until TimeoutStopSec expired and systemd killed the whole
  # cgroup. Every switch/reboot therefore logged
  #   lxc-osee.service: State 'stop-sigterm' timed out. Killing.
  #   lxc-osee.service: Failed with result 'timeout'.
  # and tore the container down abruptly, taking any x2go session with it.
  #
  # `lxc-stop -t` requests a clean shutdown (init gets SIGPWR/SIGTERM) and only
  # hard-kills after the timeout, so normal shutdowns finish in a couple of
  # seconds. -n/--kill is deliberately not used.
  stopScript = pkgs.writeShellScript "${containerName}-stop" ''
    set -euo pipefail

    # Nothing to do if the container is not running (or not even defined).
    if ! ${pkgs.lxc}/bin/lxc-info -n ${containerName} -P ${lxcHome} -s \
      | ${pkgs.gnugrep}/bin/grep -q RUNNING; then
      echo "${containerName} is not running; nothing to stop"
      exit 0
    fi

    exec ${pkgs.lxc}/bin/lxc-stop \
      -n ${containerName} \
      -P ${lxcHome} \
      -t ${toString shutdownTimeoutSec}
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
        # Restart on failure, but bounded: an unbounded on-failure restart
        # turned a single start failure (a bindfs/sudo or lxc error) into a
        # storm -- the old counter reached 104 restarts in one boot, retrying
        # every 10s forever and spamming the journal and every switch. Give up
        # after a handful of attempts; `systemctl --user reset-failed` clears
        # the counter once the cause is fixed.
        StartLimitIntervalSec = "300s";
        StartLimitBurst = 5;
      };

      Service = {
        Type = "simple";
        # Unlike the old launcher, which only bindfs-mounted and never started
        # the container, this mounts and then starts it, in order.
        ExecStartPre = "${mountScript}";
        ExecStart = "${startScript}";
        # Shut the container down through lxc rather than by signalling
        # lxc-start, which never forwards it to the container's init.
        ExecStop = "${stopScript}";
        # Unit-level, so they do not disturb the sudoers match on the argv.
        Environment = [
          "BINDFS_SOURCE=${mount.source}"
          "BINDFS_TARGET=${mount.target}"
        ];
        # Restart on failure; the start limit in [Unit] bounds the retries.
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStartSec = "75s";
        # Must exceed the `lxc-stop -t` timeout in stopScript, otherwise systemd
        # kills lxc-stop mid-shutdown and the container is SIGKILLed anyway.
        TimeoutStopSec = "${toString stopTimeoutSec}s";
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
