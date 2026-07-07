{ inputs
, name
, outPath
, pkgs
, profiles
, ...
}:
{
  imports = [
    inputs.lanzaboote.nixosModules.lanzaboote
    inputs.sops-nix.nixosModules.sops

    profiles.nixos.boot.secure-boot-tools
    profiles.nixos.boot.usb-removable
    profiles.nixos.desktop.i3
    profiles.nixos.hardware.clock-sync
    profiles.nixos.home-manager.deadbeef
    profiles.nixos.impermanence.module
    profiles.nixos.laptop.default
    profiles.nixos.nix.flake-inputs
    profiles.nixos.nixpkgs.allow-unfree
    profiles.nixos.nixpkgs.local-overlays
    profiles.nixos.sops.persist-root-age-key-file
    profiles.nixos.sops.persist-root-ssh
    profiles.nixos.users.deadbeef-sops
    profiles.nixos.workstation.android
    profiles.nixos.workstation.full
    profiles.nixos.workstation.pentesting
  ];

  networking = {
    hostName = name;
    networkmanager.enable = true;
  };

  security.pam.services.login.enableGnomeKeyring = true;

  sops.defaultSopsFile = "${outPath}/secrets/${name}-default.yaml";

  local.workstation.android.enable = true;

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "qemu-system-x86_64-uefi" ''
      qemu-system-x86_64 \
        -bios ${pkgs.OVMF.fd}/FV/OVMF.fd \
        "$@"
    '')
  ];
}
