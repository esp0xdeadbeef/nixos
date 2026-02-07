{ pkgs, lib, ... }:
{
  systemd.network.networks."10-lan1010-uplink" = {
    matchConfig.Name = "br-vlan1010";

    networkConfig = {
      ConfigureWithoutCarrier = true;
      DHCP = "no";
      IPv6AcceptRA = false;

      # you are routing on this box
      IPv6Forwarding = true;

      # FIX: this is the valid [Network] switch for PD-on-downstream
      DHCPPrefixDelegation = true;

      # sane defaults for a routed L3 segment
      LinkLocalAddressing = "ipv6";
    };

    # FIX: the delegated prefix wiring lives here
    # (NixOS: dhcpV6PrefixDelegationConfig -> dhcpPrefixDelegationConfig) :contentReference[oaicite:1]{index=1}
    dhcpPrefixDelegationConfig = {
      # upstream where the DHCPv6 client runs (your ISP side)
      UplinkInterface = "ppp0";

      # pick a stable subnet id (0..65535). 1 is fine for a single downstream.
      SubnetId = 1;

      # have networkd announce the delegated prefix on this downstream
    };

    addresses = [
      { Address = "10.255.255.1/29"; }
    ];

    routes = [
      {
        Destination = "192.168.1.0/24";
        Gateway = "10.255.255.3";
      }
      {
        Destination = "192.168.2.0/24";
        Gateway = "10.255.255.3";
      }
    ];
  };
}
