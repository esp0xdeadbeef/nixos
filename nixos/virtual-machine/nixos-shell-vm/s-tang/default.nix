{ config, lib, profiles, ... }:

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

  # Single NIC on the cobalt LAN trunk; tap VLAN 90 (unlock plane).
  boot.kernelParams = [ "net.ifnames=0" ];

  systemd.network.enable = true;

  systemd.network.netdevs."10-unlock" = {
    netdevConfig = {
      Name = "unlock";
      Kind = "vlan";
    };
    vlanConfig.Id = 90;
  };

  systemd.network.networks."10-eth0" = {
    matchConfig.Name = "eth0";
    vlan = [ "unlock" ];
    linkConfig.RequiredForOnline = false;
  };

  systemd.network.networks."10-unlock" = {
    matchConfig.Name = "unlock";
    networkConfig = {
      Address = "10.2.90.10/24";
      IPv6AcceptRA = false;
      LLDP = false;
    };
    routes = [
      { Gateway = "10.2.90.1"; Destination = "10.2.10.0/24"; }
      { Gateway = "10.2.90.1"; Destination = "10.2.20.0/24"; }
      { Gateway = "10.2.90.1"; Destination = "10.2.30.0/24"; }
      { Gateway = "10.2.90.1"; Destination = "10.2.31.0/24"; }
      { Gateway = "10.2.90.1"; Destination = "10.2.50.0/24"; }
      { Gateway = "10.2.90.1"; Destination = "10.2.51.0/24"; }
      { Gateway = "10.2.90.1"; Destination = "10.2.60.0/24"; }
    ];
    linkConfig.RequiredForOnline = false;
  };

  services.tang = {
    enable = true;
    listenStream = [ "10.2.90.10:7500" ];
    # The unlock tenant subnet is the only permitted source.
    ipAddressAllow = [
      "10.2.10.0/24"
      "10.2.20.0/24"
      "10.2.30.0/24"
      "10.2.31.0/24"
      "10.2.50.0/24"
      "10.2.51.0/24"
      "10.2.60.0/24"
      "10.2.90.0/24"
    ];
  };

  # Tang's server keypair must survive reboots or every bound LUKS disk loses
  # its NBDE unlock path. It lives on the VM's /persist (host bind), and the
  # fixed uid keeps ownership stable across reboots.
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
  virtualisation.qemu.networkingOptions = [
    "-nic bridge,br=br-cobalt-lan,model=virtio-net-pci"
  ];
}
