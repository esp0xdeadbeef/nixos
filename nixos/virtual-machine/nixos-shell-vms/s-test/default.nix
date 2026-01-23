# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{
  inputs,
  ...
}:
{
  # You can import other NixOS modules here
  imports = [
    inputs.nixos-shell.nixosModules.nixos-shell
    ./host
    ../../../01-general/desktop/shell-env.nix

  ];

}
