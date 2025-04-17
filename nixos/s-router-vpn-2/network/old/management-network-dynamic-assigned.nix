{ config, pkgs, lib, ... }:

let
  vlanRange = lib.range 1 10;

  vlanData = map (n: {
    name = "vlan" + (lib.fixedWidthString 3 "0" (toString n));
    id = n;
  }) vlanRange;

  # Base config per VLAN
  baseVlanConnection = v: {
    "connection" = {
      id = v.name;
      type = "vlan";
      interface-name = v.name;
    };
    "vlan" = {
      parent = "br0";
      id = v.id;
    };
    "ipv4" = {
      method = "auto";
    };
    "ipv6" = {
      method = "ignore";
    };
  };

  # Optional per-VLAN overrides
  vlanOverrides = {
    "vlan007" = {
      "ipv4" = {
        method = "manual";
        addresses = "10.0.7.5/24";
      };
    };
  };

  # Merge base config with overrides
  finalVlanConnectionFiles = builtins.listToAttrs (map (v: {
    name = "nm-connection-${v.name}";
    value = lib.recursiveUpdate (baseVlanConnection v)
      (lib.attrByPath [v.name] {} vlanOverrides);
  }) vlanData);

  # Static bridge and uplink
  baseConnectionFiles = {
    "nm-connection-br0" = {
      "connection" = {
        id = "br0";
        type = "bridge";
        interface-name = "br0";
      };
      "ipv4" = {
        method = "disabled";
      };
      "ipv6" = {
        method = "ignore";
      };
    };

    "nm-connection-enp0s19" = {
      "connection" = {
        id = "enp0s19";
        type = "ethernet";
        interface-name = "enp0s19";
        master = "br0";
        slave-type = "bridge";
      };
    };
  };

in {
  networking = {
    useDHCP = false;
    networkmanager.enable = true;

    interfaces = {
      enp0s18.useDHCP = true;
      br0.useDHCP = false;
    };

    firewall.enable = false;

    hostId = lib.mkDefault (
      builtins.substring 0 8 (builtins.hashString "md5" config.networking.hostName)
    );
  };

  # Render all .nmconnection files to the right path
  environment.etc =
    let
      renderedConnections =
        lib.mapAttrs'
          (name: cfg:
            let
              filename = "${name}.nmconnection";
              content = pkgs.writeText filename (pkgs.lib.generators.toINI {} cfg);
            in {
              name = "NetworkManager/system-connections/${filename}";
              value = {
                source = content;
                mode = "0600";
              };
            })
          (baseConnectionFiles // finalVlanConnectionFiles);
    in
      renderedConnections;
}
