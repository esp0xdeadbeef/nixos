{ config
, lib
, options
, ...
}:

let
  useSharedImpermanence =
    options ? local
    && options.local ? impermanence
    && config.local.impermanence.enable;
in
{
  config = lib.mkMerge [
    {
      # Make rootfs mostly ephemeral
      fileSystems."/" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "mode=755" ];
      };

      environment.persistence."/persist-state" = {
        hideMounts = true;

        # docker / podman state
        directories = [
          "/var/lib/docker"
          "/var/lib/containers"
        ];
      };
    }

    (lib.mkIf (!useSharedImpermanence) {
      environment.persistence."/persist" = {
        hideMounts = true;

        directories = [
          #"/var/lib"
          #"/var/log"
          "/var/lib/nixos"
          {
            directory = "/root/.ssh";
            user = "root";
            group = "root";
            mode = "0600";
          }
          {
            directory = "/root/.config/sops/age";
            user = "root";
            group = "root";
            mode = "0600";
          }
        ];

        files = [
          "/etc/machine-id"
        ];

        users.deadbeef = {
          directories = [
            ".ssh"
            "github"
          ];

          files = [
            ".zsh_history"
          ];
        };
      };
    })
  ];
}
