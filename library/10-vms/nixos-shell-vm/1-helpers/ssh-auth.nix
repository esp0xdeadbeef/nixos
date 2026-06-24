{ profiles
, ...
}:
{
  imports = [
    profiles.nixos.ssh.deadbeef-authorized-keys
  ];

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
