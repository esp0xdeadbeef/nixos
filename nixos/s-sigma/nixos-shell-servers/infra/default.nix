{ config, pkgs, ... }:

{
  systemd.services.infra-vm = {
    description = "Infra VM (nixos-shell)";
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

      # this hack is required to make sure the garbage collector is not cleaning it. The nix run at the end should have been enough ;)
      ExecStart = pkgs.writeShellScript "start-infra-vm" ''
        set -euo pipefail

        ROOT_DIR=/var/lib/nixos-shell
        KEEP=1
        VM_NAME="s-infra"

        mkdir -p "$ROOT_DIR"

        OUT="$ROOT_DIR/$VM_NAME-$(date --rfc-3339=seconds | sed 's/ /_/g')"

        nix build \
          path:/home/deadbeef/github/nixos#nixosConfigurations.$VM_NAME.config.system.build.nixos-shell \
          --out-link "$OUT"

        # Prune old GC roots
        ls -dt "$ROOT_DIR"/s-infra-* 2>/dev/null \
          | tail -n +$((KEEP+1)) \
          | xargs -r rm

        nix run path:/home/deadbeef/github/nixos#nixosConfigurations.$VM_NAME.config.system.build.nixos-shell
      '';

      #ProtectSystem = "strict";
      ProtectHome = "false";
      PrivateTmp = true;
      StateDirectory = "s-infra";
      WorkingDirectory = "/persist/nix-shell-vms";
    };
  };
   systemd.tmpfiles.rules = [
    "d /persist/nix-shell-vms 0755 root root -"
    "d /persist/infra/unifi 0755 root root -"
  ];
}
