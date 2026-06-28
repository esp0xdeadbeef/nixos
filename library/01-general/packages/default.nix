{ pkgs, ... }:
{
  imports = [
    ./1-general/archive-tools.nix
    ./1-general/tooling.nix
    ./audio/packages.nix
    ./data-tranformation/packages.nix
    ./editors/packages.nix
    ./encryption-and-password-management/packages.nix
    ./git/packages.nix
    ./graphics/packages.nix
    ./network-troubleshooting/packages.nix
    ./nix-specific/packages.nix
    ./password-managers/1password.nix
    ./scripting-languages/packages.nix
    ./services/packages.nix
    ./terminals/packages.nix
    ./terminals/terminal-optimisers/packages.nix
    ./terminals/terminal-optimisers/updatedb.nix
    ./usb-tools/packages.nix
    ./virtualization/packages.nix
  ];
}
