{
  lib,
  outPath,
  pkgs,
  ...
}:

let
  bridges = [
    "admin"
    "branch"
    "client"
    "client2"
    "dmz"
    "home-users"
    "hostile"
    "mgmt"
    "nas"
    "printer"
    "site-c-mgmt"
    "streaming"
  ];

  mkBridgeNetdev = name: {
    netdevConfig = {
      Kind = "bridge";
      Name = name;
    };
  };

  mkBridgeNetwork = name: {
    matchConfig.Name = name;
    networkConfig = {
      LinkLocalAddressing = "no";
      ConfigureWithoutCarrier = true;
    };
  };

  builders = import ./modules/client-builders.nix { inherit lib pkgs; };

  clientModules = [
    (import ./modules/site-a-clients.nix { inherit builders; })
    (import ./modules/branch-hostile-clients.nix { inherit builders pkgs; })
    (import ./modules/site-c-clients.nix { inherit builders lib pkgs; })
    (import ./modules/dmz-clients.nix { inherit builders pkgs; })
  ];
in
{
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config"
    ./sops.nix
  ];

  system.stateVersion = lib.mkForce "25.11";

  environment.systemPackages = with pkgs; [
    bind
    curl
    iproute2
    iputils
    jq
    tcpdump
    traceroute
  ];

  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.wait-online.enable = false;
  networking.useDHCP = false;
  networking.useHostResolvConf = lib.mkForce false;
  services.resolved.enable = lib.mkForce false;

  systemd.network.netdevs = lib.genAttrs bridges mkBridgeNetdev;
  systemd.network.networks = lib.genAttrs bridges mkBridgeNetwork;

  containers = lib.foldl' lib.recursiveUpdate { } clientModules;

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
  ];
  users.users.deadbeef.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
  ];
}
