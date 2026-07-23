{ config, lib, ... }:

let
  cfg = config.local.users.deadbeefSops;
in
{
  options.local.users.deadbeefSops.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Provision the deadbeef account password through sops-nix.";
  };

  config = lib.mkIf cfg.enable {
    local.users.primary.name = "deadbeef";

    sops.secrets."deadbeef-passwd" = {
      neededForUsers = true;
    };

    users.users.deadbeef = {
      hashedPasswordFile = config.sops.secrets.deadbeef-passwd.path;
      isNormalUser = true;
      openssh.authorizedKeys.keys = lib.mkDefault [ ];
    };
  };
}
