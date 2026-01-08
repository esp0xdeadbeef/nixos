{
  config,
  pkgs,
  lib,
  ...
}:

{
  networking.networkmanager.enable = true;
  networking.networkmanager.unmanaged = [ "eno4" ];

  # Prevent NM from trying to auto-configure eno3 directly
  networking.interfaces.eno3.useDHCP = false;
  networking.interfaces.enp132s0f0.useDHCP = false;

  networking.networkmanager.ensureProfiles = {
    profiles = {
      vmbr4 = {
        connection = {
          id = "vmbr4";
          type = "bridge";
          interface-name = "vmbr4";
          autoconnect = true;
        };
        bridge = {
          stp = false;
        };
        ipv4 = {
          method = "auto"; # or "manual"
        };
        ipv6 = {
          method = "ignore";
        };
      };

      vmbr4-eno3 = {
        connection = {
          id = "vmbr4-eno3";
          type = "ethernet";
          interface-name = "eno3";
          master = "vmbr4";
          slave-type = "bridge";
          autoconnect = true;
        };
        ipv4.method = "disabled";
        ipv6.method = "ignore";
      };
    };
    profiles = {
      vmbr1 = {
        connection = {
          id = "vmbr1";
          type = "bridge";
          interface-name = "vmbr1";
          autoconnect = true;
        };
        bridge = {
          stp = false;
        };
        ipv4 = {
          method = "auto"; # or "manual"
        };
        ipv6 = {
          method = "ignore";
        };
      };

      vmbr1-enp132s0f0 = {
        connection = {
          id = "vmbr1-enp132s0f0";
          type = "ethernet";
          interface-name = "enp132s0f0";
          master = "vmbr1";
          slave-type = "bridge";
          autoconnect = true;
        };
        ipv4.method = "disabled";
        ipv6.method = "ignore";
      };
    };

  };
}
