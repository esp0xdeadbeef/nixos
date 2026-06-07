{ inputs
, lib
, outPath
, pkgs
, ...
}:

let
  runtime = import ../runtime.nix;
  runtimeFacts = import ./runtime-facts.nix { inherit runtime; };
  swapfile = "/persist/swap/swapfile";
in
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.impermanence.nixosModules.impermanence
    inputs.sops-nix.nixosModules.sops
    ../sops.nix
    ../disko.nix
    ../hardware.nix
    (import ./machine-base.nix {
      inherit
        lib
        outPath
        runtime
        runtimeFacts
        ;
      pkgsForRenderer = pkgs;
    })
  ];

  swapDevices = [
    {
      device = swapfile;
    }
  ];

  s88.sRouterTestSops = {
    includeRootSecrets = false;
    includeAccessPrefixSecrets = false;
    includeNebulaProfileSecrets = true;
  };

  systemd.tmpfiles.rules = [
    "d ${runtimeFacts.runtimeSecretsDir} 0700 root root -"
    "d /run/secrets 0700 root root -"
    "L+ /run/secrets/hetzner-lighthouse-public-ipv4 - - - - ${runtimeFacts.lighthousePublicIPv4SecretPath}"
    "L+ /run/secrets/hetzner-public-ipv4 - - - - ${runtimeFacts.publicIPv4SecretPath}"
    "L+ /run/secrets/hetzner-public-ipv6 - - - - ${runtimeFacts.publicIPv6SecretPath}"
    "L+ /run/secrets/hetzner-public-ipv6-address - - - - ${runtimeFacts.publicIPv6AddressSecretPath}"
    "L+ /run/secrets/hetzner-routed-ipv6-prefixes - - - - ${runtimeFacts.routedIPv6PrefixesSecretPath}"
  ];

  systemd.services.s-router-hetzner-persist-swapfile = {
    description = "Prepare persistent btrfs swapfile for Hetzner validation builds";
    before = [ "persist-swap-swapfile.swap" ];
    requiredBy = [ "persist-swap-swapfile.swap" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig.Type = "oneshot";
    path = [
      pkgs.btrfs-progs
      pkgs.coreutils
      pkgs.util-linux
    ];
    script = ''
      set -euo pipefail

      install -d -m 0700 /persist/swap
      if [ ! -e ${swapfile} ]; then
        btrfs filesystem mkswapfile --size 8g ${swapfile}
      fi
      chmod 0600 ${swapfile}
    '';
  };
}
