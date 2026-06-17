{ config, lib, ... }:

let
  normalUserNames = lib.attrNames (
    lib.filterAttrs (_: user: user.isNormalUser or false) config.users.users
  );

  configuredPrimaryUser = config.local.users.primary.name;
  configuredPrimaryUserText =
    if configuredPrimaryUser == null then "<unset>" else configuredPrimaryUser;

  resolvedPrimaryUser =
    if configuredPrimaryUser != null then
      configuredPrimaryUser
    else if lib.length normalUserNames == 1 then
      lib.head normalUserNames
    else
      null;

  resolvedPrimaryUserHome =
    if resolvedPrimaryUser == null then
      null
    else
      config.users.users.${resolvedPrimaryUser}.home or "/home/${resolvedPrimaryUser}";
in

{
  options.local.users.primary = {
    name = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Primary interactive user for modules that need one user.
        When unset, it is inferred if exactly one normal user exists.
      '';
    };

    resolvedName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      readOnly = true;
      default = resolvedPrimaryUser;
      description = "Resolved primary interactive user for this host.";
    };

    homeDirectory = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = resolvedPrimaryUserHome;
      description = "Home directory for the primary interactive user, resolved from users.users.<name>.home.";
    };
  };

  config.assertions = [
    {
      assertion = configuredPrimaryUser != null || lib.length normalUserNames <= 1;
      message = ''
        Multiple normal users are configured (${lib.concatStringsSep ", " normalUserNames}).
        Set local.users.primary.name to select the default user for user-scoped modules.
      '';
    }
    {
      assertion = configuredPrimaryUser == null || lib.hasAttr configuredPrimaryUser config.users.users;
      message = "local.users.primary.name is set to '${configuredPrimaryUserText}', but users.users.${configuredPrimaryUserText} is not defined.";
    }
  ];
}
