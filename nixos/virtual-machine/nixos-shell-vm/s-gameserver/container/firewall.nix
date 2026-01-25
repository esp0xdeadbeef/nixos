{ ... }:
{
  networking.firewall.allowedTCPPorts = [
    25565
    25566
  ];

  networking.firewall.allowedUDPPortRanges = [
    {
      from = 2456;
      to = 2458;
    }
  ];

}
