{ lib, pkgs, ... }:

{
  networking.useNetworkd = true;

  systemd.services.s-router-clab-parent-eth0 = {
    description = "Rename the forwarded CLAB parent interface to eth0";
    requiredBy = [ "systemd-networkd.service" ];
    before = [
      "network-pre.target"
      "systemd-networkd.service"
    ];
    after = [ "systemd-udevd.service" ];
    path = [ pkgs.iproute2 ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu

      if ip link show dev eth0 >/dev/null 2>&1; then
        exit 0
      fi

      for _ in $(seq 1 100); do
        if ip link show dev clab0 >/dev/null 2>&1; then
          ip link set dev clab0 down || true
          ip link set dev clab0 name eth0
          ip link set dev eth0 up
          exit 0
        fi
        sleep 0.1
      done

      echo "missing forwarded CLAB parent interface clab0" >&2
      exit 1
    '';
  };

  systemd.network = {
    enable = true;

    networks."09-mgmt0" = {
      matchConfig.Name = "mgmt0";

      addresses = [
        { Address = "10.233.222.2/24"; }
      ];

      networkConfig = {
        ConfigureWithoutCarrier = true;
        DHCP = "no";
        LinkLocalAddressing = "no";
        IPv6AcceptRA = false;
      };

      routes = [
        {
          Destination = "0.0.0.0/0";
          Gateway = "10.233.222.1";
        }
      ];
    };

    networks."10-eth0" = {
      matchConfig.Name = "eth0";

      networkConfig = {
        ConfigureWithoutCarrier = true;
        DHCP = "no";
        LinkLocalAddressing = "no";
        IPv6AcceptRA = false;
      };
    };
  };

  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;
}
