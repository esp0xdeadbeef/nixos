# ./host/impermanence.nix
{ config, lib, ... }:

{
  environment.persistence."/persist" = {
    hideMounts = true;

    directories = [
      "/etc/ssh"
      "/var/lib"
      "/var/log"
      "/root/.ssh"
    ];

    files = [
      "/etc/machine-id"
    ];

    # This is the important bit for your case:
    users.deadbeef = {
      directories = [
        #    "Downloads"
        #    "Documents"
        #    ".cache"
        #    ".config"
        #    ".local"
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

}
