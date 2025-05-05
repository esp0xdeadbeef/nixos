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
  # make sure this appears in your profile’s bin dir
  home.packages = [
    osepStart
  ];

  # (optional) if you want to run it at login automatically:
  home.activation.xsessionCommands = ''
    /home/deadbeef/.nix-profile/bin/osep-lxc-start &
  '';

  # Ensure systemd user support is on
  # services.systemd.user = {
  #   enable = true;
  # };

  # Define a user‐level service
  # systemd.user.services."osep-lxc-start" = {
  #   enable      = true;                    # <— make sure it's enabled
  #   description = "Start the osep-lxc container";
  #   after       = [ "default.target" ];    # run after your session is up
  #   wantedBy    = [ "default.target" ];    # hook into the default session

  #   serviceConfig = {
  #     Type      = "oneshot";
  #     ExecStart = startScript;
  #     # keep it “active” so systemd knows it's done but still up
  #     RemainAfterExit = true;
  #     StandardOutput  = "journal";
  #     StandardError   = "journal";
  #   };
  # };
  systemd.user.services."osep-lxc-start" = {
    Unit = {
      Description = "Start the osep-lxc container";
      # user-mode can’t reliably order against system-bus units,
      # so we just wait for “network-online.target” in the user session
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      # ① give the network a moment to come up
      ExecStartPre = [
        # sleep for 5 seconds
        # "${pkgs.coreutils}/bin/sleep 5"
        # then wait up to 60s for the lxcbr0 bridge to exist
        # "${pkgs.bash}/bin/bash -c \
        # \"timeout 60 ${pkgs.coreutils}/bin/sh -c 'until ${pkgs.iproute2}/bin/ip link show lxcbr0 >/dev/null 2>&1; do sleep 1; done'\""
      ];
      # ② start lxc in-foreground with DEBUG logging
      ExecStart = "${pkgs.writeShellScript "osep-lxc-start-svc" ''
        #!${pkgs.bash}/bin/bash --noprofile --norc
        exec ${pkgs.lxc}/bin/lxc-start \
          -F -n osep-lxc \
          --logfile=/home/deadbeef/osep-lxc.log \
          --logpriority=DEBUG
      ''}";
      Restart = "on-failure";
      RestartSec = "10s"; # back off between retries
      TimeoutStartSec = "75s"; # must exceed the 60s poll+5s sleep
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
