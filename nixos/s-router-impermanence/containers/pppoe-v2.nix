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
  # SOPS PPP secrets
  sops.secrets.${userSecret} = { };
  sops.secrets.${passSecret} = { };

  networking.useNetworkd = false;
  networking.networkmanager.enable = true;

  environment.systemPackages = with pkgs; [
    networkmanager
  ];
  # Create VLAN 6 for PPPoE (remove if ISP does not need VLAN)
  networking.vlans.${wanVlan}.interface = wan;
  networking.vlans.${wanVlan}.id = 6;

  # Ensure NM profile exists for PPPoE
  networking.networkmanager.ensureProfiles = {
    profiles = {
      "pppoe-wan.nmconnection" = {
        type = "pppoe";

        connection = {
          id = "pppoe-wan";
          interface-name = wanVlan; # use `${wan}` if no VLAN
          autoconnect = true;
        };

        pppoe = {
          username = "\${SECRET:${userSecret}}";
        };

        ppp = {
          password-flags = 0;
        };

        ipv4.method = "pppoe";
        ipv6.method = "auto"; # or "ignore" depending on ISP
      };
    };

    secrets."pppoe-wan.nmconnection" = {
      ppp.password = "@${config.sops.secrets.${passSecret}.path}";
    };
  };
}
