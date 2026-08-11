{ config
, pkgs
, lib
, profiles
, ...
}:
{
  imports = [
    profiles.nixos.ssh.deadbeef-authorized-keys
  ];

  services.openssh.enable = lib.mkDefault true;

  security.sudo.extraRules = [
    {
      groups = [ "wheel" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
