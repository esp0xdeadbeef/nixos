{ inputs
, lib
, outPath
, ...
}:
let
  runtime = import ../runtime.nix;
  pkgsForRenderer = inputs.nixpkgs.legacyPackages.x86_64-linux;
  runtimeFacts = import ./runtime-facts.nix { inherit runtime; };
  modelHost = import ../../../s-router-model-host.nix {
    inherit inputs lib;
    pkgs = pkgsForRenderer;
    selector = "s-router-hetzner-anywhere";
    deploymentHostName = "s-router-hetzner-anywhere";
    file = "nixos/virtual-machine/nixos-anywhere/s-router-hetzner-anywhere/default.nix";
    excludedNebulaNodeNames = [ ];
  };
  internalWan = import ./hetzner-internal-wan.nix {
    inherit lib;
    inventory = modelHost.builtHost.globalInventory or { };
    hostName = "s-router-hetzner-anywhere";
    coreNodeName = "hetz-router-core";
  };
  hostNatTarget = modelHost.nebulaRenderer.selectHostNatIngressTarget {
    forwarding = modelHost.builtHost.forwardingOut or { };
    inventory = modelHost.builtHost.globalInventory or { };
    hostName = "s-router-hetzner-anywhere";
  };
  hostNatWan = import ./hetzner-internal-wan.nix {
    inherit lib;
    inventory = modelHost.builtHost.globalInventory or { };
    hostName = "s-router-hetzner-anywhere";
    coreNodeName = hostNatTarget.targetNode or "hetz-router-core";
    uplinkName = hostNatTarget.uplink or "wan";
  };
  publicIngressFacts = modelHost.nebulaRenderer.buildNebulaPublicIngressRuntimeFacts {
    controlPlane = modelHost.builtHost.controlPlaneOut or { };
    forwarding = modelHost.builtHost.forwardingOut or { };
    inventory = modelHost.builtHost.globalInventory or { };
    hostName = "s-router-hetzner-anywhere";
    hostNatIngressTargetWan = hostNatWan;
    runtimeNode = modelHost.peerNebulaCoreNode;
    lighthousePublicIPv4SecretPath = "/run/secrets/hetzner-lighthouse-public-ipv4";
    runtimePublicIPv4SecretPath = "/run/secrets/hetzner-public-ipv4";
    runtimeContainerName = modelHost.peerNebulaCoreName;
  };
  renderedAndOverlayContainers = lib.recursiveUpdate modelHost.renderedContainers modelHost.overlayContainers;
  endpointContainers = import ./endpoint-containers.nix { inherit lib pkgsForRenderer modelHost; };
  accessSecrets = import ./access-prefix-runtime-secrets.nix {
    nebulaRenderer = modelHost.nebulaRenderer;
    runtimeSecretsDir = runtimeFacts.runtimeSecretsDir;
    secretNames = modelHost.accessPrefixSecretNames;
    containers = renderedAndOverlayContainers;
  };
  coreContainer = modelHost.nebulaRenderer.runtimeContainerNameForHost {
    inventory = modelHost.builtHost.globalInventory or { };
    hostName = "s-router-hetzner-anywhere";
    logicalName = "hetz-router-core";
  };
in
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.impermanence.nixosModules.impermanence
    inputs.sops-nix.nixosModules.sops
    ../../../nixos-shell-vm/s-router-test/sops.nix
    (modelHost.builtHost.artifactModule or { })
    (modelHost.nebulaRenderer.buildExternalLighthouseNixosModule {
      pkgs = pkgsForRenderer;
      nebulaRuntimePlan = modelHost.localPlan;
    })
    modelHost.bootstrapModule
    (import "${inputs.network-renderer-nixos}/s88/ControlModule/module/public-ingress.nix" {
      inherit lib;
      pkgs = pkgsForRenderer;
      controlPlane = modelHost.builtHost.controlPlaneOut or { };
      inventory = modelHost.builtHost.globalInventory or { };
      hostName = "s-router-hetzner-anywhere";
      runtimeFacts.publicIngress = publicIngressFacts.publicIngress;
    })
    ../disko.nix
    ../hardware.nix
    (import ./machine-base.nix { inherit lib outPath pkgsForRenderer runtime runtimeFacts; })
    (import ./host-networking.nix {
      inherit lib runtimeFacts;
      nebulaRuntime = {
        inherit internalWan;
        renderedNetdevs = modelHost.renderedHost.netdevs or { };
        hostNetworks =
          builtins.removeAttrs
            (lib.mapAttrs (_: network: builtins.removeAttrs network [ "dhcpConfig" ]) (modelHost.renderedHost.networks or { }))
            [ "20-eth0" "30-br-wan" ];
      };
    })
    (import ./runtime-addresses.nix { inherit lib pkgsForRenderer runtimeFacts; nebulaRuntime = { inherit internalWan; }; })
  ];

  assertions = [
    {
      assertion = runtime.publicIPv4Gateway != null && runtime.primaryInterfaceMac != null && runtime.primaryInterface != null;
      message = "runtime.nix must be generated from the Hetzner spawn output without public address literals";
    }
  ];

  s88.sRouterTestSops = {
    includeRootSecrets = false;
    includeAccessPrefixSecrets = false;
    includeNebulaProfileSecrets = true;
  };

  systemd.tmpfiles.rules = [
    "d ${runtimeFacts.runtimeSecretsDir} 0700 root root -"
    "d /run/secrets 0700 root root -"
    "L+ /run/secrets/hetzner-lighthouse-public-ipv4 - - - - ${runtimeFacts.lighthousePublicIPv4SecretPath}"
    "L+ /run/secrets/hetzner-public-ipv4 - - - - ${runtimeFacts.publicIPv4SecretPath}"
    "L+ /run/secrets/hetzner-public-ipv6 - - - - ${runtimeFacts.publicIPv6SecretPath}"
  ] ++ accessSecrets.tmpfilesRules;

  environment.etc."s-router-test/hetzner-runtime.json".text = builtins.toJSON (
    runtime
    // {
      publicIPv4SecretPath = runtimeFacts.publicIPv4SecretPath;
      publicIPv6SecretPath = runtimeFacts.publicIPv6SecretPath;
      publicIPv6AddressSecretPath = runtimeFacts.publicIPv6AddressSecretPath;
      routedIPv6PrefixesSecretPath = runtimeFacts.routedIPv6PrefixesSecretPath;
    }
  );
  environment.etc."network-renderer/network-renderer-nebula.json".text = builtins.toJSON {
    overlays = builtins.attrNames (modelHost.localPlan.overlays or { });
    nodes = builtins.attrNames (modelHost.localPlan.nodes or { });
  };

  containers = lib.recursiveUpdate (lib.recursiveUpdate accessSecrets.containers endpointContainers) {
    ${coreContainer}.config = { ... }: {
      imports = [ ((renderedAndOverlayContainers.${coreContainer} or { }).config or { }) ];
      systemd.network.networks."10-eth0" = lib.mkForce {
        matchConfig.Name = "eth0";
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = false;
        };
        address = [
          internalWan.coreAddress4
          internalWan.coreAddress6
        ];
        routes = [
          { Gateway = internalWan.coreGateway4; }
          { Gateway = internalWan.coreGateway6; }
        ];
      };
    };
  };
}
