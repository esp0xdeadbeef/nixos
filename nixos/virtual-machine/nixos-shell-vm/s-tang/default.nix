{ config, lib, profiles, relativeRepo, ... }:

let
  dnsRuntime = import (relativeRepo.sourcePath "prod-network/testing/dns-runtime-addresses-cobalt.nix");
  requesterValues = builtins.attrValues dnsRuntime.requesters;
  tangAllowedSubnets = map (r: r.clientIpv4) requesterValues ++ map (r: r.clientIpv6) requesterValues;
in

{
  imports = [
    profiles.nixos.nixos-shell-host.common
  ];

  # No per-VM SOPS/deadbeef password; SSH keys only.
  local.nixosShellHost.secrets.enable = false;

  # The common profile disables the sops-backed password, so define the
  # login user here (SSH keys come from the ssh-auth helper).
  users.users.deadbeef = {
    isNormalUser = true;
    group = "deadbeef";
  };
  users.groups.deadbeef = { };

  # Single NIC on the cobalt LAN trunk. The host itself only ever joins the
  # mgmt tenant (VLAN 10); the Tang server runs in a container attached to the
  # unlock tenant (VLAN 90).
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

    "10-unlock" = {
      netdevConfig = {
        Name = "unlock";
        Kind = "vlan";
      };
      vlanConfig.Id = 90;
    };

    "20-tang-br" = {
      netdevConfig = {
        Name = "tang-br";
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
      ];
      linkConfig.RequiredForOnline = false;
    };

    # Host management on the mgmt tenant.
    "10-mgmt" = {
      matchConfig.Name = "mgmt";
      networkConfig.DHCP = "yes";
    };

    # The unlock VLAN is handed to the tang container via a host bridge.
    "10-unlock" = {
      matchConfig.Name = "unlock";
      networkConfig.Bridge = "tang-br";
      linkConfig.RequiredForOnline = false;
    };

    "20-tang-br" = {
      matchConfig.Name = "tang-br";
      networkConfig = { };
    };
  };

  # Tang server runs in a container on the unlock tenant. The host has no
  # address on that VLAN; the container's gateway is the access-unlock router
  # (10.2.90.1) reachable through the trunk.
  containers.tang = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "tang-br";
    localAddress = "10.2.90.2/24";

    bindMounts."/var/lib/tang" = {
      hostPath = "/persist/var/lib/tang";
      isReadOnly = false;
    };

    config = { lib, ... }: {
      systemd.network.enable = false;
      networking.useDHCP = false;

      networking.interfaces.eth0.ipv4.addresses = [
        {
          address = "10.2.90.10";
          prefixLength = 24;
        }
      ];
      networking.defaultGateway = "10.2.90.1";

      services.tang = {
        enable = true;
        # Bind all interfaces (the container only has eth0 = 10.2.90.10); the
        # ipAddressAllow eBPF filter still restricts sources to the tenants.
        # "7500" binds [::]:7500 dual-stack, so it serves both IPv4 and IPv6.
        listenStream = [ "7500" ];
        ipAddressAllow = tangAllowedSubnets;
      };

      # Fixed uid keeps the persisted keypair ownership stable across reboots.
      users.users.tang = {
        isSystemUser = true;
        uid = 4000;
        group = "tang";
      };
      users.groups.tang.gid = 4000;

      systemd.services."tangd@".serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = "tang";
        Group = "tang";
      };
    };
  };

  # Tang's server keypair must survive reboots or every bound LUKS disk loses
  # its NBDE unlock path. The container bind-mounts it from /persist.
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/tang";
      user = "tang";
      group = "tang";
      mode = "0700";
    }
  ];

  virtualisation.cores = 2;
  virtualisation.memorySize = 1024;
  virtualisation.diskSize = 2048;
  # Only the cobalt trunk NIC; no user-mode NAT (the guest agent socket is the
  # management channel, and the mgmt VLAN 10 provides the host network).
  virtualisation.qemu.networkingOptions = lib.mkForce [
    "-nic bridge,br=br-cobalt-lan,model=virtio-net-pci"
  ];
}
