{ inputs
, config
, lib
, name
, relativeRepo
, profiles
, ...
}:
let
  hostName = name;
  installDisk = "/dev/vda";
  nebulaSopsFile = relativeRepo.sourcePath "secrets/s-gamma.yaml";
in
{
  networking.hostName = lib.mkForce hostName;

  # s-gamma offloads to the whole builder fleet (it is a server, not an
  # interactive laptop), so it keeps the default `server` class and does not
  # drop the laptop builders.
  local.nix.remoteBuilderClient.class = "server";

  imports = [
    inputs.disko.nixosModules.disko
    profiles.nixos.mail.mailbox-sets
    profiles.nixos.network.nebula-mesh
    profiles.nixos.users.deadbeef-ssh
    profiles.nixos.nix.remote-builder-client
    inputs.sops-nix.nixosModules.sops

    ./base.nix
    ./github-token.nix
    ./impermanence.nix
    ./network.nix
    ./packages.nix
    ./cert.nix
    ./dns.nix
    ./hardware.nix
    ./health.nix
    ./mail.nix
    ./meet.nix
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
    # Discover every hosted mailbox set secret. The account allow-list remains
    # explicit so external client-only credentials never reach this server.
    names = profiles.mail.inventory.hostedMailboxSets;
    accountNames = profiles.mail.inventory.hostedMailAccounts;
  };

  sops.secrets = lib.genAttrs [
    "nebula-ca-crt"
    "nebula-host-crt"
    "nebula-host-key"
    "nebula-lighthouse-public-ip"
    "nebula-cobalt-lighthouse-public-ip"
  ]
    (_: {
      sopsFile = nebulaSopsFile;
    });

  system.stateVersion = "26.05";
}
