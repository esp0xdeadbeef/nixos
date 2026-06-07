{ inputs
, lib
, pkgs
, sRouterTestClientsLabProfile ? {
    labSource = "active-lab";
  }
, ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;

  cpm =
    inputs.network-cpm.libBySystem.${system}
      or inputs.network-cpm.lib
      or (throw "s-router-test-clients: missing network-cpm API");

  labPath = "${inputs.network-labs}/${sRouterTestClientsLabProfile.labSource}";

  labInputs = {
    intentPath = "${labPath}/intent.nix";
    inventoryPath = "${labPath}/inventory.nix";
    sopsPath = "${labPath}/sops.nix";
  };

  cpmOutput =
    if cpm ? emulatedClients && cpm.emulatedClients ? buildFromPaths then
      cpm.emulatedClients.buildFromPaths labInputs
    else if cpm ? clients && cpm.clients ? emulateFromPaths then
      cpm.clients.emulateFromPaths labInputs
    else if cpm ? clientFixtures && cpm.clientFixtures ? buildFromPaths then
      cpm.clientFixtures.buildFromPaths labInputs
    else
      throw "s-router-test-clients: CPM API must expose emulatedClients.buildFromPaths, clients.emulateFromPaths, or clientFixtures.buildFromPaths";

  labIntent = cpmOutput.intent or import labInputs.intentPath;
  labInventory = cpmOutput.inventory or import labInputs.inventoryPath;
  runtimeTargets = cpmOutput.runtimeTargets or { };
  hostNetwork = cpmOutput.hostNetwork or cpmOutput.renderedHost or { };

  hostNetworks = builtins.mapAttrs
    (_: network: builtins.removeAttrs network [ "dhcpConfig" ])
    (hostNetwork.networks or { });

  builders = import ./client-builders.nix { inherit lib pkgs; };

  siteName = cpmOutput.siteName or "nixos";
  clientAccessCount = cpmOutput.clientAccessCount or 2;

  clientContainers =
    cpmOutput.containers
      or cpmOutput.emulatedClients
      or cpmOutput.clientFixtures
      or lib.foldl' lib.recursiveUpdate { } [
        (import ./nixos-clients.nix {
          inherit builders lib siteName;
          clientTenant = "client";
          clientCount = clientAccessCount;
        })
        (import ./model-site-clients.nix {
          inherit builders lib pkgs runtimeTargets;
          intent = labIntent;
          inventory = labInventory;
          inherit siteName;
        })
        (import ./model-site-clients.nix {
          inherit builders lib pkgs runtimeTargets;
          intent = labIntent;
          inventory = labInventory;
          siteName = "clab";
          endpointAddressing = "dhcp";
        })
        (import ./branch-hostile-clients.nix { inherit builders pkgs; })
        (import ./dmz-clients.nix { inherit builders pkgs; })
      ];
in
{
  imports = [
    labInputs.sopsPath
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
    tmux
    traceroute
    tshark
  ];

  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.wait-online.enable = false;
  networking.useDHCP = false;
  networking.useHostResolvConf = lib.mkForce false;
  services.resolved.enable = lib.mkForce true;

  systemd.network.netdevs = hostNetwork.netdevs or { };

  systemd.network.networks = lib.recursiveUpdate hostNetworks {
    "30-vlan2".networkConfig.DHCP = "ipv4";
  };

  _module.args.renderedHostNetwork = {
    hostName = hostNetwork.hostName or "s-router-test-clients";
    bridgeNameMap = hostNetwork.bridgeNameMap or { };
    bridges = hostNetwork.bridges or { };
    netdevs = hostNetwork.netdevs or { };
    networks = hostNetworks;
    containers = clientContainers;
    clientAccessCount = clientAccessCount;
    hostValidation = {
      requireDefaultRoutes = true;
      requireHostResolver = true;
      requirePublicIpv4Ping = true;
      requirePublicIpv6Ping = true;
    };
  };

  containers = clientContainers;
}
