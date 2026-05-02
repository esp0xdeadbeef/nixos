{
  inputs,
  lib,
  outPath,
  pkgs,
  ...
}:

let
  api = inputs.network-renderer-nixos.lib;

  identity = {
    enterpriseName = "esp0xdeadbeef";
    siteName = "site-a";
    boxName = builtins.baseNameOf (builtins.toString ./.);
  };

  fabric = {
    intentPath = "${inputs.network-labs}/examples/s-router-test-three-site/intent.nix";
    inventoryPath = "${inputs.network-labs}/examples/s-router-test-three-site/inventory-nixos.nix";
  };

  sliceArgs = {
    inherit (identity) boxName;
    inherit (fabric) intentPath inventoryPath;
  };

  builtHost = api.renderer.buildHostFromPaths {
    inherit (fabric) intentPath inventoryPath;
    selector = identity.boxName;
    file = "nixos/virtual-machine/nixos-shell-vm/s-router-test-clients/default.nix";
  };

  renderedHost = api.host.build sliceArgs;
  renderedBridges = api.bridges.build sliceArgs;

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
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    (builtHost.artifactModule or { })
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

  systemd.network.netdevs = (renderedHost.netdevs or { }) // (renderedBridges.netdevs or { });
  systemd.network.networks =
    lib.recursiveUpdate ((renderedHost.networks or { }) // (renderedBridges.networks or { }))
      {
        "30-vlan2".networkConfig.DHCP = "ipv4";
      };

  containers = lib.foldl' lib.recursiveUpdate { } clientModules;

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
  ];
  users.users.deadbeef.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
  ];
}
