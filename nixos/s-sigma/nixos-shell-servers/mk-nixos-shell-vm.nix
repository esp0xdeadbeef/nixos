{ pkgs, lib }:

name:
{
  description ? "NixOS VM (nixos-shell)",
  keep ? 1,
  workingDir ? "/persist/nix-shell-vms",
  extraTmpfiles ? [ ],
}:

let
  serviceName = "${name}-vm";
in
{
  systemd.services.${serviceName} = {
    inherit description;

    after = [ "network-online.target" "nix-daemon.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    path = [ pkgs.nix ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 10;
      User = "root";

      ExecStart = pkgs.writeShellScript "start-${serviceName}" ''
        set -euo pipefail

        ROOT_DIR=/var/lib/nixos-shell
        KEEP=${toString keep}
        VM_NAME="${name}"

        mkdir -p "$ROOT_DIR"

        OUT="$ROOT_DIR/$VM_NAME-$(date --rfc-3339=seconds | sed 's/ /_/g')"

        nix build \
          path:/home/deadbeef/github/nixos#nixosConfigurations.$VM_NAME.config.system.build.nixos-shell \
          --out-link "$OUT"

        ls -dt "$ROOT_DIR"/"$VM_NAME"-* 2>/dev/null \
          | tail -n +$((KEEP+1)) \
          | xargs -r rm

        exec nix run \
          path:/home/deadbeef/github/nixos#nixosConfigurations.$VM_NAME.config.system.build.nixos-shell
      '';

      ProtectHome = false;
      PrivateTmp = true;
      StateDirectory = name;
      WorkingDirectory = workingDir;
    };
  };

  systemd.tmpfiles.rules =
    [ "d ${workingDir} 0755 root root -" ]
    ++ extraTmpfiles;
}

