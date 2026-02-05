{ pkgs, config, ... }:
{
  environment.systemPackages = with pkgs; [ nebula ];

  services.nebula.networks.mesh = {
    enable = true;
    isLighthouse = false;

    lighthouses = [ "100.64.0.1" ];

    staticHostMap = {
      "100.64.0.1" = [
        "192.168.1.7:4242"
      ];
    };

    cert = "/persist/etc/nebula/${config.networking.hostName}.crt";
    key = "/persist/etc/nebula/${config.networking.hostName}.key";
    ca = "/persist/etc/nebula/ca.crt";

    firewall.outbound = [
      {
        host = "any";
        port = "any";
        proto = "any";
      }
    ];
    firewall.inbound = [
      {
        host = "any";
        port = "any";
        proto = "any";
      }
    ];
  };

}
