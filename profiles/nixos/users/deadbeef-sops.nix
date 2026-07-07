{ config, lib, ... }:
{
  local.users.primary.name = "deadbeef";

  sops.secrets."deadbeef-passwd" = {
    neededForUsers = true;
  };

  users.users.deadbeef = {
    hashedPasswordFile = config.sops.secrets.deadbeef-passwd.path;
    isNormalUser = true;
    openssh.authorizedKeys.keys = lib.mkDefault [ ];
  };
}
