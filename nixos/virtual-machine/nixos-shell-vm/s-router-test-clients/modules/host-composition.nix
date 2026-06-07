{ inputs
, lib
, pkgs
, sRouterTestClientsLabProfile ? {
    labSource = "active-lab";
    labSelector = "s-router-test-clients";
  }
, ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;

  cpm =
    inputs.network-cpm.libBySystem.${system}
      or inputs.network-cpm.lib
      or inputs.network-renderer-nixos.lib;

  labPath = "${inputs.network-labs}/${sRouterTestClientsLabProfile.labSource}";

  cpmInput = {
    intentPath = "${labPath}/intent.nix";
    inventoryPath = "${labPath}/inventory.nix";
    sopsPath = "${labPath}/sops.nix";
    selector = sRouterTestClientsLabProfile.labSelector;
    file = "nixos/virtual-machine/nixos-shell-vm/s-router-test-clients/default.nix";
  };

  cpmOutput =
    if cpm ? emulatedClients && cpm.emulatedClients ? buildFromPaths then
      cpm.emulatedClients.buildFromPaths cpmInput
    else if cpm ? renderer && cpm.renderer ? buildHostFromPaths then
      cpm.renderer.buildHostFromPaths cpmInput
    else
      throw "s-router-test-clients: CPM API must expose emulatedClients.buildFromPaths or renderer.buildHostFromPaths";

  renderedHost = cpmOutput.renderedHost or { };

  renderedHostNetworks = builtins.mapAttrs
    (_: network: builtins.removeAttrs network [ "dhcpConfig" ])
    (renderedHost.networks or { });

  labIntent = cpmOutput.intent or import cpmInput.intentPath;
  labInventory = cpmOutput.inventory or import cpmInput.inventoryPath;
  runtimeTargets = cpmOutput.runtimeTargets or { };

  siteName = cpmOutput.siteName or "nixos";

  builders = import ./client-builders.nix { inherit lib pkgs; };

  clientAccessCount = cpmOutput.clientAccessCount or 2;

  modelClients =
    cpmOutput.emulatedClients
      or cpmOutput.clients
      or null;

  clientContainers =
    if modelClients != null then
      modelClients
    else
      lib.foldl' lib.recursiveUpdate { } [
        (import ./nixos-clients.nix {
          inherit builders lib;
          inherit siteName clientAccessCount;
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
    (cpmOutput.artifactModule or { })
    cpmInput.sopsPath
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

  systemd.network.netdevs = renderedHost.netdevs or { };

  systemd.network.networks = lib.recursiveUpdate renderedHostNetworks {
    "30-vlan2".networkConfig.DHCP = "ipv4";
  };

  _module.args.renderedHostNetwork = {
    hostName = renderedHost.hostName or sRouterTestClientsLabProfile.labSelector;
    bridgeNameMap = renderedHost.bridgeNameMap or { };
    bridges = renderedHost.bridges or { };
    netdevs = renderedHost.netdevs or { };
    networks = renderedHostNetworks;
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
