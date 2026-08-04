{ lib, pkgs, ... }:

let
  pinnedMac = "02:14:58:52:89:41";
in
{
  networking.useDHCP = false;
  networking.useNetworkd = true;

  systemd.services.s-llm-inference-veth-mac = {
    description = "Apply pinned MAC address to veth3 before DHCP";
    wantedBy = [ "sysinit.target" ];
    before = [ "systemd-networkd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.iproute2 ];
    script = ''
      set -euo pipefail
      for _ in $(seq 1 40); do
        if ip link show veth3 >/dev/null 2>&1; then
          ip link set dev veth3 down || true
          ip link set dev veth3 address ${lib.escapeShellArg pinnedMac}
          ip link set dev veth3 up
          exit 0
        fi
        sleep 0.25
      done
      echo "[network] ERROR: veth3 did not appear before networkd startup" >&2
      exit 1
    '';
  };

  systemd.services.systemd-networkd = {
    after = [ "s-llm-inference-veth-mac.service" ];
    requires = [ "s-llm-inference-veth-mac.service" ];
  };

  systemd.network = {
    enable = true;

    networks."10-veth3" = {
      matchConfig.Name = "veth3";

      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = "yes";
      };

      dhcpV4Config = {
        UseDNS = "yes";
        UseDomains = "yes";
      };
    };
  };

  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;
}
