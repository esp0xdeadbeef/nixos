{ ... }:
{
  systemd.network.networks."20-lan1010" = {
    matchConfig.Name = "lan1010";

    addresses = [
      { Address = "10.255.255.1/30"; }
    ];

    networkConfig = {
      IPv6Forwarding = true;
      IPv6SendRA = false; # we run radvd ourselves
    };

    # Assign a /64 from the uplink's delegated prefix to this LAN.
    # These knobs are from systemd.network's [IPv6PrefixDelegation] section. :contentReference[oaicite:7]{index=7}
    ipv6PrefixDelegationConfig = {
      UplinkInterface = "ppp0";
      Assign = true;
      AssignAddresses = true;
      Announce = false;
      Token = "::1";

      # Pin to "first" /64 inside the PD so it's stable.
      SubnetId = 0;
    };
  };
}

