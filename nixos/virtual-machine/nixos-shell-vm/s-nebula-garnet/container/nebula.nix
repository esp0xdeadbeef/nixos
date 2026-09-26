{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    nebula
    tcpdump
  ];

  services.nebula.networks.garnet = {
    enable = true;
    isLighthouse = true;
    isRelay = true;

    cert = "/persist/etc/nebula/beacon.crt";
    key = "/persist/etc/nebula/beacon.key";
    ca = "/persist/etc/nebula/ca.crt";

    # The garnet overlay is the site-to-site service path; the lighthouse
    # listens on 4243 (the remote-access mesh stays on 4242).
    listen = {
      host = "[::]";
      port = 4243;
    };

    # Temporary while the two cores are onboarded, matching s-nebula's
    # open firewall posture. Tighten once the cores are proven.
    firewall = {
      inbound = [
        {
          host = "any";
          port = "any";
          proto = "any";
        }
      ];
      outbound = [
        {
          host = "any";
          port = "any";
          proto = "any";
        }
      ];
    };
  };
}
