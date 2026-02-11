# ./host-config/default.nix
# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  name,
  outPath,
  ...
}:
{
  # You can import other NixOS modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/nixos):
    # outputs.nixosModules.example
    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
    # inputs.nvf.nixosModules.default
    # inputs.nixvim.nixosModules.nixvim
    "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/vm-storage-persist.nix"
    "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/debug-packages.nix"
    "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/ssh-auth.nix"
    "${outPath}/library/01-general/desktop/shell-env.nix"
    ./vm-settings.nix
    ./restart-container.nix
    ./network.nix
    ./ssh.nix
    ./impermanence.nix
    ./persist-state-disk.nix
  ];

  networking.hostName = name;

  sops.defaultSopsFile = "${outPath}/secrets/${config.networking.hostName}.yaml";
  # This will automatically import SSH keys as age keys
  sops.age.sshKeyPaths = [ "/persist/root/.ssh/id_ed25519" ];
  sops.age.keyFile = "/persist/root/.config/sops/age/keys.txt";

  nixpkgs = {
    overlays = [
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages
    ];
    config = {
      allowUnfree = true;
    };
  };

  nix =
    let
      flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
    in
    {
      settings = {
        experimental-features = "nix-command flakes";
        flake-registry = "";
        nix-path = config.nix.nixPath;
      };
      channel.enable = false;

      registry = lib.mapAttrs (_: flake: { inherit flake; }) flakeInputs;
      nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
    };

  time.timeZone = "Europe/Amsterdam";

  security.pam.services.login.enableGnomeKeyring = true;
  environment.interactiveShellInit = ''
    ZSH_THEME=alanpeabody
  '';

  sops.secrets."deadbeef-passwd" = {
    neededForUsers = true;
  };

  users.users = {
    deadbeef = {
      hashedPasswordFile = config.sops.secrets.deadbeef-passwd.path;
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };
  };

  system.stateVersion = "24.11";
}
