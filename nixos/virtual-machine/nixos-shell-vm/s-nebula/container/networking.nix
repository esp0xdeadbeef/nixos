{ lib
, pkgs
, ...
}:

let
  macSecretPath = "/run/secrets/s-nebula-container-mac";
in

{
  networking.useDHCP = false;
  networking.useNetworkd = true;

  systemd.services.s-nebula-container-veth0-mac = {
    description = "Apply secret-backed MAC address to veth0";
    wantedBy = [ "sysinit.target" ];
    before = [ "systemd-networkd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.iproute2
    ];
    script = ''
      set -euo pipefail

      if [ ! -r ${lib.escapeShellArg macSecretPath} ]; then
        echo "[network] ERROR: ${macSecretPath} is not readable" >&2
        exit 1
      fi

      mac="$(tr -d '[:space:]' < ${lib.escapeShellArg macSecretPath})"
      if ! printf '%s\n' "$mac" | grep -Eq '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'; then
        echo "[network] ERROR: ${macSecretPath} does not contain a valid MAC address" >&2
        exit 1
      fi

      for _ in $(seq 1 40); do
        if ip link show veth0 >/dev/null 2>&1; then
          ip link set dev veth0 down || true
          ip link set dev veth0 address "$mac"
          ip link set dev veth0 up
          exit 0
        fi
        sleep 0.25
      done

      echo "[network] ERROR: veth0 did not appear before networkd startup" >&2
      exit 1
    '';
  };

  systemd.services.systemd-networkd = {
    after = [ "s-nebula-container-veth0-mac.service" ];
    requires = [ "s-nebula-container-veth0-mac.service" ];
  };

  systemd.network = {
    enable = true;

    networks."10-veth0" = {
      matchConfig.Name = "veth0";

      networkConfig = {
        DHCP = "yes"; # v4 + v6
        IPv6AcceptRA = "yes";
      };

      dhcpV4Config = {
        UseDNS = "yes";
        UseDomains = "yes";
      };

      dhcpV6Config = {
        UseDNS = "yes";
      };
    };
  };

  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;
}
