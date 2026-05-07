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
    boxName = "s-router-test-clients";
  };

  labResolvedInventoryPath =
    builtins.toFile "lab-sigma-resolved-inventory-nixos.nix" ''
      import ${inputs.network-labs}/labs/lab-s-sigma/s-router-test-three-site/getResolvedInventory.nix { renderer = "nixos"; }
    '';

  fabric = {
    intentPath = "${inputs.network-labs}/labs/lab-s-sigma/s-router-test-three-site/intent.nix";
    inventoryPath = labResolvedInventoryPath;
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

  builders = import ./client-builders.nix { inherit lib pkgs; };

  clientModules = [
    (import ./site-a-clients.nix { inherit builders; })
    (import ./branch-hostile-clients.nix { inherit builders pkgs; })
    (import ./dmz-clients.nix { inherit builders pkgs; })
  ];

  clientContainers = lib.foldl' lib.recursiveUpdate { } clientModules;

  renderedHostNetwork = {
    hostName = renderedHost.hostName or identity.boxName;
    bridgeNameMap = renderedBridges.bridgeNameMap or { };
    bridges = renderedBridges.bridges or { };
    netdevs = (renderedHost.netdevs or { }) // (renderedBridges.netdevs or { });
    networks = (renderedHost.networks or { }) // (renderedBridges.networks or { });
    containers = clientContainers;
    hostValidation = {
      requireDefaultRoutes = true;
      requireHostResolver = true;
      requirePublicIpv4Ping = true;
      requirePublicIpv6Ping = true;
    };
  };

  mkClientBridge =
    name:
    {
      netdevConfig = {
        Kind = "bridge";
        Name = name;
      };
    };

  mkClientBridgeNetwork =
    name:
    {
      matchConfig.Name = name;
      linkConfig = {
        ActivationPolicy = "always-up";
        RequiredForOnline = "no";
      };
      networkConfig = {
        ConfigureWithoutCarrier = true;
        DHCP = "no";
        IPv6AcceptRA = false;
      };
    };

  localOnlyClientBridges = [ ];
in
{
  imports = [
    (builtHost.artifactModule or { })
  ];

  system.stateVersion = lib.mkForce "25.11";

  environment.systemPackages = with pkgs; [
    bind
    curl
    iproute2
    iputils
    jq
    ripgrep
    tcpdump
    traceroute
  ];

  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.wait-online.enable = false;
  networking.useDHCP = false;
  networking.useHostResolvConf = lib.mkForce false;
  services.resolved.enable = lib.mkForce false;

  systemd.network.netdevs =
    (renderedHost.netdevs or { })
    // (renderedBridges.netdevs or { })
    // lib.genAttrs localOnlyClientBridges mkClientBridge;
  systemd.network.networks =
    lib.recursiveUpdate
      (
        (renderedHost.networks or { })
        // (renderedBridges.networks or { })
        // lib.genAttrs localOnlyClientBridges mkClientBridgeNetwork
      )
      {
        "30-vlan2".networkConfig.DHCP = "ipv4";
      };

  _module.args = {
    inherit renderedHostNetwork;
  };

  containers = clientContainers;

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
  ];
  users.users.deadbeef.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
  ];
}
