{ config
, inputs
, name
, outPath
, profiles
, ...
}:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops

    profiles.nixos.core
    profiles.nixos.impermanence.module
    profiles.nixos.nix.flake-inputs
    profiles.nixos.nixpkgs.allow-unfree
    profiles.nixos.nixpkgs.local-overlays
    profiles.nixos.shell.zsh-prompt
    profiles.nixos.sops.persist-root-age-key-file
    profiles.nixos.sops.persist-root-ssh
    profiles.nixos.users.deadbeef-sops

    "${outPath}/library/01-general/desktop/shell-env.nix"
    "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/debug-packages.nix"
    "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/ssh-auth.nix"
    "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/vm-storage-persist.nix"
    "${outPath}/modules/nixos/local-users.nix"
  ];

  home-manager.backupFileExtension = "hm-backup";

  networking.hostName = name;

  sops.defaultSopsFile = "${outPath}/secrets/${config.networking.hostName}.yaml";

  time.timeZone = "Europe/Amsterdam";

  security.pam.services.login.enableGnomeKeyring = true;

  local.shell.zshPrompt.enable = true;

  users.users.deadbeef.extraGroups = [ "wheel" ];

  system.stateVersion = "24.11";
}
