{ inputs
, lib
, config
, name
, relativeRepo
, profiles
, ...
}:

let
  keyFor = host: lib.fileContents (relativeRepo.sourcePath "ssh-keys/deadbeef/${host}.pub");
in
{
  imports = [
    inputs.nixos-shell.nixosModules.nixos-shell
    profiles.nixos.nix.flake-inputs
    profiles.nixos.nixpkgs.allow-unfree
    profiles.nixos.nixpkgs.local-overlays

    (relativeRepo.module "library/10-vms/default.nix")
    (relativeRepo.module "library/01-general/desktop/shell-env.nix")
    (relativeRepo.module "library/10-vms/nixos-shell-vm/1-helpers/debug-packages.nix")
  ];

  networking.hostName = name;
  networking.useDHCP = lib.mkDefault true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [
    (keyFor "l-portal")
    (keyFor "l-esp")
  ];

  users.users.deadbeef = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = config.users.users.root.openssh.authorizedKeys.keys;
  };

  security.sudo.wheelNeedsPassword = false;

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
