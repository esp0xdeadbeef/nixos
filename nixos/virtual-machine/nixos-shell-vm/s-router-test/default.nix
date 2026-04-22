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
    intentPath = ./intent.nix;
    inventoryPath = ./inventory.nix;
  };

  sliceArgs = {
    inherit (identity) enterpriseName siteName boxName;
    inherit (fabric) intentPath inventoryPath;
  };

  disabledContainers = { };

  commonContainerOptions = {
    autoStart = true;
    additionalCapabilities = [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
    ];
  };

  builtHost = api.renderer.buildHostFromPaths {
    inherit (fabric) intentPath inventoryPath;
    selector = identity.boxName;
    file = "nixos/virtual-machine/nixos-shell-vm/s-router-test/default.nix";
  };

  resolvedHostContext =
    (builtHost.hostContext or { })
    // {
      hostname = identity.boxName;
      enterpriseName = identity.enterpriseName;
      siteName = identity.siteName;
      matchedEnterprises = [ identity.enterpriseName ];
      matchedSites = [ identity.siteName ];
    };

  renderedHost = api.host.build sliceArgs;

  renderedBridges = api.bridges.build sliceArgs;

  renderedContainers = api.containers.buildForBox (
    sliceArgs
    // {
      disabled = disabledContainers;
      defaults = commonContainerOptions;
    }
  );

  deploymentHostName =
    let
      fromBuiltHost =
        if
          builtHost ? hostContext
          && builtins.isAttrs builtHost.hostContext
          && builtHost.hostContext ? deploymentHostName
          && builtins.isString builtHost.hostContext.deploymentHostName
        then
          builtHost.hostContext.deploymentHostName
        else
          null;
    in
    if fromBuiltHost != null then fromBuiltHost else renderedHost.deploymentHostName or null;

  renderedHostNetwork = {
    hostName = renderedHost.hostName or identity.boxName;
    inherit deploymentHostName;
    bridgeNameMap = renderedBridges.bridgeNameMap or { };
    bridges = renderedBridges.bridges or { };
    netdevs =
      (renderedHost.netdevs or { })
      // (renderedBridges.netdevs or { });
    networks =
      (renderedHost.networks or { })
      // (renderedBridges.networks or { });
    containers = renderedContainers;
    debug = {
      host = renderedHost.debug or { };
      bridges = renderedBridges.debug or { };
      containers = builtins.attrNames renderedContainers;
    };
  };

  builders = import ./modules/container-builders.nix { inherit lib pkgs; };

  testContainers = import ./modules/test-containers.nix {
    inherit (builders) mkTenantEndpoint;
  };

  overlayContainers = import ./modules/overlay-containers.nix {
    inherit renderedHostNetwork;
    inherit (builders) mkNebulaNode mkNebulaProfileMount;
  };

  dmzContainers = import ./modules/dmz-containers.nix {
    inherit renderedHostNetwork;
    inherit (builders) mkDmzEndpoint;
  };
in
{
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ./mount-utils.nix
    ./sops.nix
    (import ./modules/nebula-bootstrap.nix {
      inherit pkgs renderedHostNetwork;
    })
  ];

  system.stateVersion = lib.mkForce "25.11";

  environment.systemPackages = with pkgs; [
    ethtool
    iproute2
    iputils
    jq
    lsof
    mtr
    nftables
    nebula
    openssh
    procps
    strace
    tcpdump
    traceroute
  ];

  _module.args = {
    inherit identity fabric;
    globalInventory = builtHost.globalInventory or { };
    hostContext = resolvedHostContext;
    intent = builtHost.fabricInputs or { };
    fabricInputs = builtHost.fabricInputs or { };
    compilerOut = builtHost.compilerOut or { };
    forwardingOut = builtHost.forwardingOut or { };
    controlPlaneOut = builtHost.controlPlaneOut or { };
    inherit renderedHostNetwork;
  };

  environment.etc."network-renderer/network-renderer-nixos.json".text =
    builtins.toJSON {
      inherit identity fabric;
      host = renderedHost.debug or { };
      bridges = renderedBridges.debug or { };
      containers = builtins.attrNames renderedContainers;
    };

  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.wait-online.enable = false;
  networking.useDHCP = false;
  networking.useHostResolvConf = lib.mkForce false;
  services.resolved.enable = lib.mkForce false;
  systemd.network.netdevs =
    (renderedHost.netdevs or { })
    // (renderedBridges.netdevs or { });

  # Management uplink (eth0.2 -> vlan2) should get DHCPv4 so the host itself
  # has connectivity. `mgmt` is a tenant L2 bridge (VLAN 330), not the host mgmt
  # uplink; expect the host address on `vlan2` instead.
  systemd.network.networks =
    lib.recursiveUpdate
      (
        (renderedHost.networks or { })
        // (renderedBridges.networks or { })
      )
      {
        "30-vlan2".networkConfig.DHCP = "ipv4";
      };

  containers =
    renderedContainers
    // testContainers
    // overlayContainers
    // dmzContainers;
}
