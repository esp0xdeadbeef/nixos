{ config
, pkgs
, lib
, ...
}:

{
  networking.networkmanager.enable = lib.mkForce false;
  systemd.network.enable = true;

  sops.secrets."vlan2-mac" = { };

  # vlan2's MAC is identity-bearing (DHCP client-id + provider lease) and lives
  # in secrets/s-tau-root.yaml under `vlan2-mac`. systemd-networkd creates the
  # netdev before sops is guaranteed ready, so a oneshot service applies it.
  systemd.services.s-tau-vlan2-mac = {
    description = "Apply vlan2 MAC from sops";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-networkd.service" ];
    wants = [ "systemd-networkd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.iproute2 pkgs.coreutils pkgs.systemd ];
    script = ''
      set -euo pipefail
      mac="$(tr -d '[:space:]' < '${config.sops.secrets."vlan2-mac".path}')"
      for _ in $(seq 1 40); do
        if ip link show vlan2 >/dev/null 2>&1; then
          ip link set dev vlan2 address "$mac"
          networkctl reconfigure vlan2 || true
          exit 0
        fi
        sleep 0.25
      done
      echo "[network] vlan2 did not appear" >&2
      exit 1
    '';
  };

  ###### PURE L2 BRIDGE ######
  systemd.network.netdevs."10-vmbr4" = {
    netdevConfig = {
      Name = "vmbr4";
      Kind = "bridge";
    };

  };

  systemd.network.netdevs."15-vlan2" = {
    netdevConfig = {
      Name = "vlan2";
      Kind = "vlan";
    };
    vlanConfig.Id = 2;
  };

  ###### PHYSICAL NIC -> BRIDGE ######
  systemd.network.networks."10-eno3" = {
    matchConfig.Name = "eno3";
    networkConfig = {
      Bridge = "vmbr4";
    };
  };

  systemd.network.networks."20-vlan2" = {
    matchConfig.Name = "vlan2";
    networkConfig = {
      DHCP = "ipv4";
      LinkLocalAddressing = "no";
    };
    dhcpV4Config = {
      ClientIdentifier = "mac";
      SendRelease = false;
      MaxAttempts = "infinity";
      UseRoutes = false;
      UseGateway = false;
    };
  };

  ###### BRIDGE: NO IP, NO DHCP ######
  systemd.network.networks."10-vmbr4" = {
    matchConfig.Name = "vmbr4";
    networkConfig = {
      # Keep a host management address on VLAN 2 on the bridge master. Putting
      # this on eno3 steals VLAN 2 replies before the bridge can forward them
      # back to nixos-shell VM tap devices.
      VLAN = [ "vlan2" ];
    };
  };

  ###### LIBVIRT ######
  virtualisation.libvirtd = {
    enable = true;
    allowedBridges = [
      "vmbr4"
      "vmbr1"
    ];
  };

  ###### REQUIRED FOR BRIDGED TRAFFIC ######
  networking.firewall.checkReversePath = false;
}
