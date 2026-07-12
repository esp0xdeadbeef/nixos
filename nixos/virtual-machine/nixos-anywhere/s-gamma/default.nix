{ inputs
, lib
, name
, outPath
, profiles
, ...
}:
let
  system = "x86_64-linux";
  hostName = name;
  installDisk = "/dev/vda";
in
{
  networking.hostName = lib.mkForce hostName;

  imports = [
    inputs.disko.nixosModules.disko
    profiles.nixos.impermanence.module
    profiles.nixos.mail.mailbox-sets
    inputs.sops-nix.nixosModules.sops

    ./network.nix
    ./cert.nix
    ./dns.nix
    ./hardware.nix
    ./mail.nix
    ./web.nix

    (import ./disko.nix {
      disk = installDisk;
    })

    (import ./machine-base.nix {
      inherit lib outPath;
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      inherit hostName installDisk;
    })
  ];

  local.mail.mailboxSets = {
    enable = true;
    accountNames = [
      "mail-account-001"
      "mail-account-002"
      "mail-account-003"
      "mail-account-004"
      "mail-account-005"
    ];
  };

  system.stateVersion = "26.05";
}
