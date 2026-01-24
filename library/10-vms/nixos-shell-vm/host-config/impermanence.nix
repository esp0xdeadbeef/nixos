{ config, lib, ... }:

{
  environment.persistence."/persist" = {
    hideMounts = true;

    directories = [
      "/var/lib"
      "/var/log"
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
      ];
      files = [
        ".zsh_history"
        ".zshrc"
      ];
    };
  };
  # Make rootfs mostly ephemeral
  fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "mode=755" ];
  };
  systemd.tmpfiles.rules = [
    "f /persist/home/deadbeef/.zshrc 0644 deadbeef users -"
  ];
}
