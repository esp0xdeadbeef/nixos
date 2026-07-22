{ relativeRepo
, pkgs
, profiles
, ...
}:
{
  imports = [
    profiles.nixos.nixpkgs.allow-unfree
    profiles.nixos.core
    profiles.nixos.shell.zsh-prompt

    (relativeRepo.module "modules/nixos/cuda-cache.nix")
    (relativeRepo.module "modules/nixos/local-users.nix")

    ./desktop/applet-nm.nix
    ./desktop/fonts.nix
    ./desktop/packages.nix
    ./desktop/screen-recording.nix
    ./desktop/shell-env.nix
    ./desktop/users-and-groups.nix
    ./desktop/xdg-portal.nix
    ./network/firewall.nix
    ./network/nat-lxc.nix
    ./network/nmcli.nix
    ./password-cracking
    ./packages/1-general/archive-tools.nix
    ./packages/1-general/tooling.nix
    ./packages/audio/packages.nix
    ./packages/data-tranformation/packages.nix
    ./packages/editors/packages.nix
    ./packages/encryption-and-password-management/packages.nix
    ./packages/git/packages.nix
    ./packages/graphics/packages.nix
    ./packages/network-troubleshooting/packages.nix
    ./packages/nix-specific/packages.nix
    ./packages/password-managers/1password.nix
    ./packages/scripting-languages/packages.nix
    ./packages/services/packages.nix
    ./packages/terminals/packages.nix
    ./packages/terminals/terminal-optimisers/packages.nix
    ./packages/terminals/terminal-optimisers/updatedb.nix
    ./packages/usb-tools/packages.nix
    ./packages/virtualization/packages.nix
    ./security
    ./secrets/import-secrets.nix
    ./system/autoupdate.nix
    ./system/locale.nix
    ./system/garbage-collection.nix
    ./terminals/tmux/settings.nix
    ./time/timezone.nix
    ./virtualization-as-host/general.nix
    ./virtualization-as-host/libvirt.nix
    ./virtualization-as-host/podman.nix
    ./virtualization-as-host/lxc.nix
  ];
}
