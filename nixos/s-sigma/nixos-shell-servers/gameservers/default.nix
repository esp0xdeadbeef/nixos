{ config, pkgs, ... }:

{
  systemd.services.gameserver-vm = {
    description = "Gameserver VM (nixos-shell)";
    after = [
      "network-online.target"
      "nix-daemon.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.nix ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 10;
      User = "root";

      # Inline logic, no external scripts
      ExecStart = pkgs.writeShellScript "start-gameserver-vm" ''
        set -euo pipefail

        ROOT_DIR=/var/lib/nixos-shell
        KEEP=2

        mkdir -p "$ROOT_DIR"

        OUT="$ROOT_DIR/gameservers-$(date --rfc-3339=seconds | sed 's/ /_/g')"

        nix build \
          path:/home/deadbeef/github/nixos#nixosConfigurations.s-gameservers.config.system.build.nixos-shell \
          --out-link "$OUT"

        # Prune old GC roots
        ls -dt "$ROOT_DIR"/gameservers-* 2>/dev/null \
          | tail -n +$((KEEP+1)) \
          | xargs -r rm

        nix run path:/home/deadbeef/github/nixos#nixosConfigurations.s-gameservers.config.system.build.nixos-shell
      '';

      # Allow nix + root dir writes
      #ReadWritePaths = [
      #  "/nix"
      #  "/var/lib/nixos-shell"
      #  "/home/deadbeef"
      #  "/persist/minecraft"
      #];

      #ProtectSystem = "strict";
      ProtectHome = "false";
      PrivateTmp = true;
      StateDirectory = "gameserver-vm";
      WorkingDirectory = "/var/lib/gameserver-vm";
    };
  };
}
