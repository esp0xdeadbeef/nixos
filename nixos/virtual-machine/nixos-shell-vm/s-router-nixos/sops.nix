{
  config,
  lib,
  ...
}:

let
  cfg = config.s88.sRouterTestSops;
  mkRootSecret = _name: {
    owner = "root";
    mode = "0400";
  };
  nebulaProfileNames = [
    "nixos-router-core-nebula"
    "hetz-router-lighthouse"
    "hetz-router-nebula-core"
  ];
  mkNebulaProfileSecret = profileName: suffix: targetName: {
    name = "nebula-profile-${profileName}-${suffix}";
    value = {
      owner = "root";
      mode = "0400";
      path = "/persist/nebula-runtime/profiles/${profileName}/${targetName}";
    };
  };
  nebulaProfileSecrets = builtins.listToAttrs (
    lib.concatMap (profileName: [
      (mkNebulaProfileSecret profileName "ca-crt" "ca.crt")
      (mkNebulaProfileSecret profileName "crt" "${profileName}.crt")
      (mkNebulaProfileSecret profileName "key" "${profileName}.key")
    ]) nebulaProfileNames
  );
in
{
  options.s88.sRouterTestSops = {
    hetznerAccessPrefixSecretNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    includeRootSecrets = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    includeAccessPrefixSecrets = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    includeNebulaProfileSecrets = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };

  config = {
    sops.secrets =
      (if cfg.includeRootSecrets then
        {
          pppoe-username = mkRootSecret "pppoe-username";
          pppoe-password = mkRootSecret "pppoe-password";
          hetzner-public-ipv4 = mkRootSecret "hetzner-public-ipv4";
          hetzner-lighthouse-public-ipv4 = mkRootSecret "hetzner-lighthouse-public-ipv4";
          hetzner-public-ipv6 = mkRootSecret "hetzner-public-ipv6";
          hetzner-primary-interface-mac = mkRootSecret "hetzner-primary-interface-mac";
        }
      else
        { })
      // (if cfg.includeAccessPrefixSecrets then
        lib.genAttrs cfg.hetznerAccessPrefixSecretNames mkRootSecret
      else
        { })
      // (if cfg.includeNebulaProfileSecrets then nebulaProfileSecrets else { });

    systemd.tmpfiles.rules = lib.optionals cfg.includeNebulaProfileSecrets (
      map (
        profileName: "d /persist/nebula-runtime/profiles/${profileName} 0700 root root -"
      ) nebulaProfileNames
    );
  };
}
