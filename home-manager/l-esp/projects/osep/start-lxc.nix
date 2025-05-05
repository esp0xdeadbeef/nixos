{
  config,
  pkgs,
  lib,
  ...
}:

let
  osepStart = pkgs.writeShellScriptBin "osep-lxc-start" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    # Defined in nixos/nixos/l-esp/osep/bind-to-lxc.nix
    # bindfs mount (no password prompt if you’ve added this to sudoers)
    # sudo ${pkgs.bindfs}/bin/bindfs \
    #   --uid-offset=100000 --gid-offset=100900 \
    #   /home/deadbeef/github/osep/shared \
    #   /home/deadbeef/.local/share/lxc/osep-lxc/rootfs/mnt/

    # start the LXC container
    ${pkgs.lxc}/bin/lxc-start osep-lxc

    # attach into it as root
    ${pkgs.lxc}/bin/lxc-attach -n osep-lxc \
      --clear-env -v "HOME=/root"
  '';
  startScript = "${config.home.homeDirectory}/.nix-profile/bin/osep-lxc-start";
in
{
  home.packages = [
    osepStart
  ];

  home.activation.xsessionCommands = ''
    /home/deadbeef/.nix-profile/bin/osep-lxc-start &
  '';

  systemd.user.services."osep-lxc-start" = {
    Unit = {
      Description = "Start the osep-lxc container";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      ExecStartPre = [
        
      ];
      ExecStart = "${pkgs.writeShellScript "osep-lxc-start-svc" ''
        #!${pkgs.bash}/bin/bash --noprofile --norc
        exec ${pkgs.lxc}/bin/lxc-start \
          -F -n osep-lxc \
          --logfile=/home/deadbeef/osep-lxc.log \
          --logpriority=DEBUG
      ''}";
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
