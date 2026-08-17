{ lib, ... }:

{
  # Dedicated Tang (NBDE) server for the cobalt unlock plane (VLAN 90).
  #
  # The "cobalt-unlock" SSID terminates on the ALFA AP inside the
  # s-router-cobalt VM and is bridged to the unlock tenant (10.2.90.0/24,
  # VLAN 90). l-envil taps that VLAN out of the br-cobalt-lan trunk so the
  # Tang server is reachable by stage-1 clients without giving them a path to
  # any other cobalt plane. The unlock plane reaches Tang and nothing else.
  systemd.network.netdevs."20-unlock-vlan" = {
    netdevConfig = {
      Name = "unlock-vlan";
      Kind = "vlan";
    };
    vlanConfig.Id = 90;
  };

  systemd.network.networks."10-unlock-vlan" = {
    matchConfig.Name = "unlock-vlan";
    networkConfig = {
      Address = "10.2.90.10/24";
      IPv6AcceptRA = false;
      LLDP = false;
    };
    linkConfig.RequiredForOnline = false;
  };

  services.tang = {
    enable = true;
    listenStream = [ "10.2.90.10:7500" ];
    # The unlock tenant subnet is the only permitted source.
    ipAddressAllow = [ "10.2.90.0/24" ];
  };

  # Tang's server keypair must survive reboots or every bound LUKS disk loses
  # its NBDE unlock path (it is persisted under /var/lib/tang). DynamicUser
  # would chown that persisted state to a fresh ephemeral UID on every boot,
  # so pin the service to a fixed system user instead.
  users.users.tang = {
    isSystemUser = true;
    group = "tang";
  };
  users.groups.tang = { };

  systemd.services."tangd@".serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "tang";
    Group = "tang";
  };

  networking.firewall.interfaces."unlock-vlan".allowedTCPPorts = [ 7500 ];
}
