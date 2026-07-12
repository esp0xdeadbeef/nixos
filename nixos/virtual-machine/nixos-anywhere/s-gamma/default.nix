{ inputs
, config
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
  runtimeSopsFile = ../../../../secrets/s-gamma-runtime.yaml;
in
{
  networking.hostName = lib.mkForce hostName;

  imports = [
    inputs.disko.nixosModules.disko
    profiles.nixos.impermanence.module
    profiles.nixos.mail.mailbox-sets
    profiles.nixos.web.redirect-domains
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
