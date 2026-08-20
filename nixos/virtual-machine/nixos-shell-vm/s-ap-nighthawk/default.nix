{ config, lib, pkgs, inputs, relativeRepo, profiles, ... }:

# Dedicated AP VM for the Nighthawk AXE3000 (mt7925u). The device is passed
# through via USB; this VM only bridges WiFi clients onto the cobalt LAN trunk
# VLANs (30 = clients, 31 = clients-vpn) and joins mgmt (VLAN 10) for SSH.
let
  hostName = "s-ap-nighthawk";
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

  # The mt7925u firmware only reports the 2.4GHz bit in hw_path, so mt76 never
  # registers the 5GHz band. Force it; 6GHz is already present in the
  # capability TLV.
  boot.kernelPatches = [
    {
      name = "mt7925-force-5ghz";
      patch = ../../../../patches/mt7925-force-5ghz.patch;
    }
  ];

  boot.kernelParams = [ "net.ifnames=0" ];

  systemd.network.enable = true;

  systemd.network.netdevs = {
    "10-mgmt" = {
      netdevConfig = {
        Name = "mgmt";
        Kind = "vlan";
      };
      vlanConfig.Id = 10;
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
        "clients"
        "clients-vpn"
      ];
      linkConfig.RequiredForOnline = false;
    };

    # Host management on the mgmt tenant.
    "10-mgmt" = {
      matchConfig.Name = "mgmt";
      networkConfig.DHCP = "yes";
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

    "20-ap-clients" = {
      matchConfig.Name = "ap-clients";
      networkConfig = { };
    };
    "20-ap-clients-vpn" = {
      matchConfig.Name = "ap-clients-vpn";
      networkConfig = { };
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
  # Only the cobalt trunk NIC; no user-mode NAT (the guest agent socket is the
  # management channel, and the mgmt VLAN 10 provides the host network).
  virtualisation.qemu.networkingOptions = lib.mkForce [
    "-nic none"
    "-nic bridge,br=br-cobalt-lan,model=virtio-net-pci"
  ];
}
