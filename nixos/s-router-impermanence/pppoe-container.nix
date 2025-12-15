{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{
  system.stateVersion = "24.11";

  services.dbus.enable = true;

  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  environment.systemPackages = with pkgs; [
    networkmanager
    ppp
    iproute2
    tcpdump
    kea
  ];

  ############################
  # NETWORKING
  ############################
  networking.useNetworkd = false;
  networking.networkmanager.enable = true;
  networking.useDHCP = false;

  ############################
  # STATIC IPs (ANYTHING WORKS)
  ############################
  networking.interfaces = {
    lan2.ipv4.addresses = [
      {
        address = "192.168.1.1";
        prefixLength = 24;
      }
    ];
    lan3.ipv4.addresses = [
      {
        address = "192.168.3.1";
        prefixLength = 24;
      }
    ];
    lan10.ipv4.addresses = [
      {
        address = "192.168.10.1";
        prefixLength = 24;
      }
    ];
    lan1000.ipv4.addresses = [
      {
        address = "192.168.100.1";
        prefixLength = 24;
      }
    ];
    lan1010.ipv4.addresses = [
      {
        address = "192.168.101.1";
        prefixLength = 24;
      }
    ];
  };

  ############################
  # NAT
  ############################
  networking.nat = {
    enable = true;
    externalInterface = "ppp0";
    internalInterfaces = [
      "lan2"
      "lan3"
      "lan10"
      "lan1000"
      "lan1010"
    ];
  };

  ############################
  # KEA DHCPv4 (ALL INTERFACES)
  ############################
  environment.etc."kea/kea-dhcp4.conf".text = ''
    {
      "Dhcp4": {
        "interfaces-config": {
          "interfaces": [ "lan2", "lan3", "lan10", "lan1000", "lan1010" ]
        },
        "lease-database": {
          "type": "memfile",
          "persist": true,
          "name": "/var/lib/kea/dhcp4.leases"
        },
        "subnet4": [
          { "id": 1, "subnet": "192.168.1.0/24" },
          { "id": 2, "subnet": "192.168.3.0/24" },
          { "id": 3, "subnet": "192.168.10.0/24" },
          { "id": 4, "subnet": "192.168.100.0/24" },
          { "id": 5, "subnet": "192.168.101.0/24" }
        ]
      }
    }
  '';

  systemd.services.kea-dhcp4 = {
    description = "Kea DHCPv4 Server";
    wantedBy = [ "multi-user.target" ];

    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      ExecStart = pkgs.writeShellScript "kea-dhcp4-execstart" ''
        set -euo pipefail
        set -x

        mkdir -p /run/kea || true 
        mkdir -p /var/lib/kea || true
        chmod 0755 /run/kea

        exec ${pkgs.kea}/bin/kea-dhcp4 -c /etc/kea/kea-dhcp4.conf
      '';

      Restart = "always";
      RestartSec = 2;
    };
  };

  ############################
  # PPPoE (NM)
  ############################
  environment.etc."NetworkManager/system-connections/isp-pppoe.nmconnection" = {
    mode = "0600";
    text = ''
      [connection]
      id=pppoe-wan
      type=pppoe
      interface-name=wan

      [pppoe]
      username=/run/secrets/pppoe-username
      password=/run/secrets/pppoe-password

      [ipv4]
      method=auto

      [ipv6]
      method=disabled
    '';
  };

}
