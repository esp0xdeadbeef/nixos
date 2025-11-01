{
  config,
  lib,
  pkgs,
  ...
}:

let
  wan = "ens19";
  wanVlan = "ens19.6";
  userSecret = "pppoe-username";
  passSecret = "pppoe-password";
in
{
  networking.useNetworkd = false;
  networking.networkmanager.enable = true;
  networking.networkmanager.unmanaged = [
    "ens18"
    "ens21"
  ];

  sops.secrets.${userSecret} = { };
  sops.secrets.${passSecret} = { };

  networking.networkmanager.ensureProfiles.profiles = {
    "wan-vlan6" = {
      connection = {
        id = "wan-vlan6";
        type = "vlan";
        interface-name = wanVlan; # ens19.6
        autoconnect = true;
      };

      vlan = {
        id = 6;
        parent = wan;
      };

      ipv4.method = "disabled";
      ipv6.method = "ignore";
    };

    "pppoe-wan" = {
      connection = {
        id = "pppoe-wan";
        type = "pppoe";
        autoconnect = true;
      };

      pppoe = {
        parent = "ens19.6";
        username = "@/run/secrets/${userSecret}";
      };

      ppp = {
        password = "@/run/secrets/${passSecret}";
        password-flags = 0;
      };

      ipv4.method = "auto";
      ipv6.method = "auto";
    };
  };
}
