{ config
, inputs
, lib
, name
, relativeRepo
, profiles
, ...
}:
let
  cfg = config.local.nixosShellHost;
in
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

  options.local.nixosShellHost.secrets.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Use the per-VM sops file and SOPS-backed deadbeef password.";
  };

  config = lib.mkMerge [
    {
      home-manager.backupFileExtension = "hm-backup";

      local.users.deadbeefSops.enable = lib.mkDefault cfg.secrets.enable;

      networking.hostName = name;

      time.timeZone = "Europe/Amsterdam";

      security.pam.services.login.enableGnomeKeyring = true;

      local.shell.zshPrompt.enable = true;

      users.users.deadbeef.extraGroups = [ "wheel" ];

      system.stateVersion = "24.11";
    }

    (lib.mkIf cfg.secrets.enable {
      sops.defaultSopsFile =
        relativeRepo.sourcePathMaybeMissing "secrets/${config.networking.hostName}.yaml";
    })
  ];
}
