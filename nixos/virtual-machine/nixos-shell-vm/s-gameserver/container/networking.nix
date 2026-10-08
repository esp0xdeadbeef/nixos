{ lib, ... }:

{
  # The container is attached to exactly one plane: neon dmz (VLAN 60).
  # Address it statically, matching the `s-gameserver` endpoint in
  # prod-network/testing/inventory-neon.nix (10.3.60.10) and the dmz access
  # gateway modelled for the neon site (10.3.60.1).  Static, so no device MAC
  # secret / DHCP reservation is needed for the exposed host.
  systemd.network.enable = false;
  networking.useDHCP = false;
  networking.networkmanager.enable = false;

  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "10.3.60.10";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = "10.3.60.1";

  # No IPv6 address and no default gateway6: the neon-dmz tenant declares no
  # routed IPv6 prefix, so there is no public IPv6 surface for this host
  # (see the game-server traffic type's ipv4 family in the intent).
  networking.interfaces.eth0.ipv6.addresses = lib.mkForce [ ];
}
