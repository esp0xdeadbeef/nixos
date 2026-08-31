{ config, lib, profiles, ... }:

# Cobalt nebula lighthouse VM.
#
# Mirrors the neon s-nebula lighthouse, but as a standalone VM on l-envil
# rather than a container hosted on the site-a hypervisor. It joins the
# cobalt service tenant (VLAN 20) where the router forwards nebula traffic,
# plus the mgmt tenant (VLAN 10) for SSH.
{
  imports = [
    profiles.nixos.nixos-shell-host.common
    profiles.nixos.network.nebula-lighthouse
  ];

  # No per-VM SOPS/deadbeef password; SSH keys only.
  local.nixosShellHost.secrets.enable = false;

  users.users.deadbeef = {
    isNormalUser = true;
    group = "deadbeef";
  };
  users.groups.deadbeef = { };

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

    "10-svc" = {
      netdevConfig = {
        Name = "svc";
        Kind = "vlan";
      };
      vlanConfig.Id = 20;
    };
  };

  systemd.network.networks = {
    "10-eth0" = {
      matchConfig.Name = "eth0";
      vlan = [
        "mgmt"
        "svc"
      ];
      linkConfig.RequiredForOnline = false;
    };

    # Host management on the mgmt tenant.
    "10-mgmt" = {
      matchConfig.Name = "mgmt";
      networkConfig.DHCP = "yes";
    };

    # The lighthouse listens on the svc tenant; the cobalt router forwards
    # nebula (UDP 4242) here from the fake-ISP WAN surface. Static address so
    # the intent's public-ingress endpoint stays stable.
    "10-svc" = {
      matchConfig.Name = "svc";
      address = [ "10.2.20.2/24" ];
      networkConfig = {
        IPv6AcceptRA = "yes";
      };
    };
  };

  # The nebula beacon identity (cert/key/ca) lives under /persist and is
  # provisioned out-of-band. The services.nebula module runs as
  # user/group nebula-mesh, so make the directory group-accessible.
  systemd.tmpfiles.rules = [
    "d /persist/etc/nebula 0750 root nebula-mesh -"
  ];

  virtualisation.cores = 2;
  virtualisation.memorySize = 2048;
  virtualisation.diskSize = 2048;
  # Only the cobalt trunk NIC; no user-mode NAT (the guest agent socket is
  # the management channel, mgmt VLAN 10 provides host SSH, and svc VLAN 20
  # carries the lighthouse).
  virtualisation.qemu.networkingOptions = lib.mkForce [
    "-nic none"
    "-nic bridge,br=br-cobalt-lan,model=virtio-net-pci"
  ];
}
