{ inputs
, outputs
, lib
, config
, pkgs
, name
, outPath
, ...
}:

{
  imports = [
    inputs.nixos-shell.nixosModules.nixos-shell
    "${outPath}/library/10-vms/default.nix"
    "${outPath}/library/01-general/desktop/shell-env.nix"
    "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/debug-packages.nix"
  ];

  networking.hostName = name;
  networking.useDHCP = lib.mkDefault true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMjKvRKsu7X9Ll0ymXF1+ArvggVqn3jcLoVCL0MutUzT deadbeef@l-portal"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMgBgeVe/DSMZQAY8iS1D5Db3IbyteDSW+l79ZFD8Rmg deadbeef@l-esp"
  ];

  users.users.deadbeef = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = config.users.users.root.openssh.authorizedKeys.keys;
  };

  security.sudo.wheelNeedsPassword = false;

  nixpkgs = {
    overlays = [
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages
    ];
    config.allowUnfree = true;
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

  virtualisation = {
    cores = 2;
    memorySize = 2048;
    diskSize = 8192;
    qemu.networkingOptions = lib.mkForce [
      "-nic"
      "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22"
    ];
  };

  nixos-shell.mounts = {
    mountHome = false;
    mountNixProfile = false;
  };

  system.stateVersion = "26.05";
}
