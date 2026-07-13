{ inputs
, config
, lib
, name
, outPath
, profiles
, ...
}:
let
  hostName = name;
  installDisk = "/dev/vda";
  runtimeSopsFile = outPath + "/secrets/s-gamma-runtime.yaml";
in
{
  networking.hostName = lib.mkForce hostName;

  imports = [
    inputs.disko.nixosModules.disko
    profiles.nixos.mail.mailbox-sets
    profiles.nixos.users.deadbeef-ssh
    inputs.sops-nix.nixosModules.sops

    ./base.nix
    ./github-token.nix
    ./impermanence.nix
    ./network.nix
    ./packages.nix
    ./cert.nix
    ./dns.nix
    ./hardware.nix
    ./mail.nix
    ./ssh.nix
    ./upgrade.nix
    ./web.nix

    (import ./disko.nix {
      disk = installDisk;
    })

    (import ./boot.nix {
      inherit installDisk;
    })
  ];

  local.mail.mailboxSets = {
    enable = true;
    names = profiles.mail.inventory.hostedMailboxSets;
    accountNames = profiles.mail.inventory.hostedMailAccounts;
  };

  system.stateVersion = "26.05";
}
