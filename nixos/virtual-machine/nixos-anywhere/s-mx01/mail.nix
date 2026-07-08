{ lib, ... }:
let
  privateModule = builtins.getEnv "NIXOS_MAILSERVER_PRIVATE_MODULE";
  privateModulePath = /. + privateModule;
  hasPrivateModule = privateModule != "";
in
{
  imports = lib.optionals hasPrivateModule [
    privateModulePath
  ];

  systemd.tmpfiles.rules = [
    "d /persist/secrets 0700 root root -"
    "d /persist/secrets/mail 0700 root root -"
  ];

  assertions = lib.optionals hasPrivateModule [
    {
      assertion = builtins.pathExists privateModulePath;
      message = "NIXOS_MAILSERVER_PRIVATE_MODULE points to a file that does not exist";
    }
  ];
}
