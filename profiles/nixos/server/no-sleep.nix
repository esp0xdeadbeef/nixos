{ lib, pkgs, ... }:
let
  noOpSleepService = {
    overrideStrategy = "asDropin";
    serviceConfig.ExecStart = lib.mkForce [
      ""
      "${pkgs.coreutils}/bin/true"
    ];
  };
in
{
  services.logind.settings.Login = {
    HandleHibernateKey = "ignore";
    HandleHibernateKeyLongPress = "ignore";
    HandleSuspendKey = "ignore";
    HandleSuspendKeyLongPress = "ignore";
  };

  systemd.services = lib.genAttrs [
    "systemd-hibernate"
    "systemd-hybrid-sleep"
    "systemd-suspend"
    "systemd-suspend-then-hibernate"
  ]
    (_: noOpSleepService);
}
