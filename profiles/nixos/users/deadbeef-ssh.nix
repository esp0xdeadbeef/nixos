{ lib, ... }:

{
  users.users.deadbeef = {
    isNormalUser = true;
    hashedPassword = "!";
    group = "users";
    home = "/home/deadbeef";
    openssh.authorizedKeys.keys = lib.mkDefault [ ];
  };
}
