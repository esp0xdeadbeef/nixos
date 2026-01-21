{ pkgs, ... }:
{
  imports = [
    ./vm-settings.nix
    ./start-container.nix
    ./network.nix
    ./impermanence.nix
    ./ssh.nix
    #../../../../../nixos/99-testing/enable-ssh-with-authorized-keys-and-add-NOPASSWD.nix
  ];
}
