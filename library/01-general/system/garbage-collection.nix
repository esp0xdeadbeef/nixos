{ config, pkgs, ... }:
{
  nix.gc = {
    automatic = true;
    persistent = true;
    dates = "daily";
    options = "--delete-older-than 30d";
    randomizedDelaySec = "5min";
  };

  systemd.services.nix-prune-generations = {
    description = "Prune old NixOS system generations";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''
        ${pkgs.nix}/bin/nix-env \
          --profile /nix/var/nix/profiles/system \
          --delete-generations +30
      '';
    };
  };

  systemd.timers.nix-prune-generations = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };

}
