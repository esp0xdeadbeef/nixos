{ config
, pkgs
, lib
, ...
}:

let
  oseeStart = pkgs.writeShellScriptBin "lxc-osee-start" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    # Defined in nixos/laptop/l-esp/optional/osee/lxc-osee/bind-to-lxc.nix
    # bindfs mount (no password prompt if you’ve added this to sudoers)
    # sudo ${pkgs.bindfs}/bin/bindfs \
    #   --uid-offset=100000 --gid-offset=100900 \
    #   /home/deadbeef/github/osee/shared \
    #   /home/deadbeef/.local/share/lxc/lxc-osee/rootfs/mnt/

    # start the LXC container
    ${pkgs.lxc}/bin/lxc-start lxc-osee

    # attach into it as root
    ${pkgs.lxc}/bin/lxc-attach -n lxc-osee \
      --clear-env -v "HOME=/root"
  '';
  startScript = "${config.home.homeDirectory}/.nix-profile/bin/lxc-osee-start";
in
{
  home.packages = [
    oseeStart
  ];

  home.activation.xsessionCommands = ''
    /home/deadbeef/.nix-profile/bin/lxc-osee-start &
  '';

  systemd.user.services."lxc-osee-start" = {
    Unit = {
      Description = "Start the lxc-osee container";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      ExecStartPre = [
        "${pkgs.coreutils}/bin/sleep 20"
      ];

      ExecStart = "${pkgs.writeShellScript "lxc-osee-start-svc" ''
        #!${pkgs.bash}/bin/bash --noprofile --norc
        # this is added to the sudoers:
        sudo /run/current-system/sw/bin/bindfs --uid-offset=100000 --gid-offset=100900 /home/deadbeef/github/OSEE/shared /home/deadbeef/.local/share/lxc/lxc-osee/rootfs/mnt
        exec ${pkgs.lxc}/bin/lxc-start \
          -F -n lxc-osee \
          --logfile=/tmp/lxc-osee.log \
          --logpriority=DEBUG
      ''}";
      # ExecStartPost = "${pkgs.writeShellScript "lxc-osee-stop-svc" ''
      #   #!${pkgs.bash}/bin/bash --noprofile --norc
      #   # this is added to the sudoers:
      #   sudo /run/current-system/sw/bin/umount /home/deadbeef/.local/share/lxc/lxc-osee/rootfs/mnt
      #   exec ${pkgs.lxc}/bin/lxc-stop -n lxc-osee
      # ''}";

      Restart = "on-failure";
      RestartSec = "10s"; # back off between retries
      TimeoutStartSec = "75s";
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
