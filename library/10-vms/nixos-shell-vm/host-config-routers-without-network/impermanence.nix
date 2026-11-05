{ config, lib, ... }:

{

  environment.persistence = {
    "/persist-state" = {
      hideMounts = true;

      # docker / podman state
      directories = [
        "/var/lib/docker"
        "/var/lib/containers"
      ];
    };

    "/persist" = {
      hideMounts = true;

      directories = [
        #"/var/lib"
        # Journald is volatile by default in these guests, so a failed boot
        # (e.g. egress/DNS timeouts that only appear at runtime) leaves no
        # evidence to inspect: mounting the qcow2 showed var/lib/{containers,
        # docker} and no journal at all. Persist /var/log so the guest keeps
        # its journal across restarts.
        "/var/log"
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
  };

  # Make rootfs mostly ephemeral
  fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "mode=755" ];
  };
}
