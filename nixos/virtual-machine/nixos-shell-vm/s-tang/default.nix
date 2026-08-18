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
      networking.interfaces.eth0.ipv6.addresses = [
        {
          address = "fd42:dead:beef:290::10";
          prefixLength = 64;
        }
      ];
      networking.defaultGateway = "10.2.90.1";
      networking.defaultGateway6 = "fd42:dead:beef:290::1";

      services.tang = {
        enable = true;
        # "7500" binds [::]:7500 dual-stack, so it serves both IPv4 and IPv6.
        # Source restriction is enforced by the cobalt allow-<tenant>-to-tang
        # firewall rules; the eBPF ipAddressAllow mis-filtered external TCP
        # inside the container, so it is omitted.
        listenStream = [ "7500" ];
      };

      # The tang module only creates the socket; it does not open the port in
      # the container's own nftables, so external TCP SYN is dropped (ICMP
      # echo is the only thing allowed by default, which is why ping worked
      # while curl failed).
      networking.firewall.allowedTCPPorts = [ 7500 ];
      # Allow the standard traceroute UDP probe range so the kernel replies
      # with ICMP port-unreachable (the destination hop of a UDP traceroute).
      networking.firewall.allowedUDPPorts = lib.range 33434 33523;

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
