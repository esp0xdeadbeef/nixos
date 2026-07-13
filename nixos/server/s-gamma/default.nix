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
    profiles.nixos.web.redirect-domains
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
    accountNames = [
      "mail-account-001"
      "mail-account-002"
      "mail-account-003"
      "mail-account-004"
      "mail-account-005"
    ];
  };

  local.web.redirectDomains = {
    enable = true;
    sopsFile = runtimeSopsFile;
    afterUnits = [ "${hostName}-cert-mail.service" ];
    requiresUnits = [ "${hostName}-cert-mail.service" ];
    tls = {
      enable = true;
      fullchainPath = config.sGamma.certs.mail.fullchainPath;
      keyPath = config.sGamma.certs.mail.keyPath;
    };
  };

  system.stateVersion = "26.05";
}
