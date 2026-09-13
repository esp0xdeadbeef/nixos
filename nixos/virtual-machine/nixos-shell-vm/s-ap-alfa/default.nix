{ config, lib, pkgs, inputs, relativeRepo, profiles, ... }:

# Dedicated 2.4GHz AP VM for the ALFA AWUS036NHA (rt2800usb, 148f:3070). The
# device is passed through via USB; this VM bridges the unlock (VLAN 90),
# mgmt (VLAN 10), clients (VLAN 30) and clients-vpn (VLAN 31) WiFi clients onto
# the cobalt LAN trunk. The clients/clients-vpn BSSes reuse the same
# SSID/PSK/SAE as the Nighthawk's 5GHz BSSes, so a client sees one SSID on both
# bands across the two radios.
let
  hostName = "s-ap-alfa";
in
{
  imports = [
    ./ap.nix

    profiles.nixos.nixos-shell-host.common
  ];

  _module.args.hostName = hostName;

  # No per-VM SOPS password; SSH keys only (the cobalt-wifi secret below is
  # decrypted with the VM's shared sops age key).
  local.nixosShellHost.secrets.enable = false;

  users.users.deadbeef = {
    isNormalUser = true;
    group = "deadbeef";
  };
  users.groups.deadbeef = { };

  hardware.enableAllFirmware = true;

  boot.kernelParams = [ "net.ifnames=0" ];

  networking.useNetworkd = true;
  networking.useDHCP = false;
  networking.networkmanager.enable = false;

  systemd.network.enable = true;

  systemd.network.netdevs = {
    "10-mgmt" = {
      netdevConfig = {
        Name = "mgmt";
        Kind = "vlan";
      };
      vlanConfig.Id = 10;
    };
    "10-unlock" = {
      netdevConfig = {
        Name = "unlock";
        Kind = "vlan";
      };
      vlanConfig.Id = 90;
    };
    "10-clients" = {
      netdevConfig = {
        Name = "clients";
        Kind = "vlan";
      };
      vlanConfig.Id = 30;
    };
    "10-clients-vpn" = {
      netdevConfig = {
        Name = "clients-vpn";
        Kind = "vlan";
      };
      vlanConfig.Id = 31;
    };
    "20-ap-unlock" = {
      netdevConfig = {
        Name = "ap-unlock";
        Kind = "bridge";
      };
    };
    "20-ap-mgmt" = {
      netdevConfig = {
        Name = "ap-mgmt";
        Kind = "bridge";
      };
    };
    "20-ap-clients" = {
      netdevConfig = {
        Name = "ap-clients";
        Kind = "bridge";
      };
    };
    "20-ap-clients-vpn" = {
      netdevConfig = {
        Name = "ap-clients-vpn";
        Kind = "bridge";
      };
    };
  };

  systemd.network.networks = {
    "10-eth0" = {
      matchConfig.Name = "eth0";
      vlan = [
        "mgmt"
        "unlock"
        "clients"
        "clients-vpn"
      ];
      linkConfig.RequiredForOnline = false;
    };

    # Host management on the mgmt tenant (via the ap-mgmt bridge so the
    # mgmt WiFi SSID and the host share the same VLAN 10 L2).
    "10-mgmt" = {
      matchConfig.Name = "mgmt";
      networkConfig.Bridge = "ap-mgmt";
      linkConfig.RequiredForOnline = false;
    };

    "10-unlock" = {
      matchConfig.Name = "unlock";
      networkConfig.Bridge = "ap-unlock";
      linkConfig.RequiredForOnline = false;
    };

    "10-clients" = {
      matchConfig.Name = "clients";
      networkConfig.Bridge = "ap-clients";
      linkConfig.RequiredForOnline = false;
    };

    "10-clients-vpn" = {
      matchConfig.Name = "clients-vpn";
      networkConfig.Bridge = "ap-clients-vpn";
      linkConfig.RequiredForOnline = false;
    };

    "20-ap-unlock" = {
      matchConfig.Name = "ap-unlock";
      networkConfig = { };
    };
    "20-ap-clients" = {
      matchConfig.Name = "ap-clients";
      networkConfig = { };
    };
    "20-ap-clients-vpn" = {
      matchConfig.Name = "ap-clients-vpn";
      networkConfig = { };
    };
    "20-ap-mgmt" = {
      matchConfig.Name = "ap-mgmt";
      networkConfig.DHCP = "yes";
    };
  };

  sops.secrets."cobalt-wifi" = {
    sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-wifi.yaml";
    key = "";
    path = "/run/secrets/cobalt-wifi";
  };

  virtualisation.cores = 2;
  virtualisation.memorySize = 2048;
  virtualisation.diskSize = 2048;
  virtualisation.qemu.networkingOptions = lib.mkForce [
    "-nic none"
    "-nic bridge,br=br-cobalt-lan,model=virtio-net-pci"
  ];
}
