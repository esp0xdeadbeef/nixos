{ config
, inputs
, name
, relativeRepo
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

    (relativeRepo.module "library/01-general/desktop/shell-env.nix")
    (relativeRepo.module "library/10-vms/nixos-shell-vm/1-helpers/debug-packages.nix")
    (relativeRepo.module "library/10-vms/nixos-shell-vm/1-helpers/ssh-auth.nix")
    (relativeRepo.module "library/10-vms/nixos-shell-vm/1-helpers/vm-storage-persist.nix")
    (relativeRepo.module "modules/nixos/local-users.nix")
  ];

  home-manager.backupFileExtension = "hm-backup";

  networking.hostName = name;

  sops.defaultSopsFile = relativeRepo.sourcePath "secrets/${config.networking.hostName}.yaml";

  time.timeZone = "Europe/Amsterdam";

  security.pam.services.login.enableGnomeKeyring = true;

  local.shell.zshPrompt.enable = true;

  users.users.deadbeef.extraGroups = [ "wheel" ];

  system.stateVersion = "24.11";
}
