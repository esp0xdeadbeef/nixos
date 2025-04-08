{
  config,
  pkgs,
  lib,
  ...
}:

let
  vlanRange = lib.range 1 10;
  # Build a list of tuples: [ { name = "vlan001"; id = 1; } ... ]
  vlanData = map (n: {
    name = "vlan" + (lib.fixedWidthString 3 "0" (toString n));
    id = n;
  }) vlanRange;

  vlanList = lib.listToAttrs (
    map (v: {
      name = v.name;
      value = {
        id = v.id;
        interface = "br0";
      };
    }) vlanData
  );

  generatedInterfaces = lib.listToAttrs (
    map (v: {
      name = v.name;
      value = {
        useDHCP = true;
      };
    }) vlanData
  );

in
{
  networking = {
    useNetworkd = true;
    useDHCP = false;

    vlans = vlanList;

    bridges = {
      "br0" = {
        interfaces = [ "enp0s19" ];
      };
    };

    interfaces = generatedInterfaces // {
      enp0s18.useDHCP = true;
      br0.useDHCP = false;

      # manual overide:
      # vlan007 = {
      #   ipv4.addresses = [
      #     {
      #       address = "10.0.5.5";
      #       prefixLength = 24;
      #     }
      #   ];
      # };
    };

    hostId = lib.mkDefault (
      builtins.substring 0 8 (builtins.hashString "md5" config.networking.hostName)
    );

    firewall.enable = false;
  };
}
