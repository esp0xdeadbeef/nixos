{ inputs
, lib
, config
, relativeRepo
, profiles
, ...
}:
let
  system = "x86_64-linux";
  labSource = "active-lab";
  hostName = "s-router-test-clients";
  labPath = "${inputs.network-labs}/${labSource}";
  intentPath = "${labPath}/intent-${hostName}.nix";
  inventoryPath = "${labPath}/inventory-${hostName}.nix";
  clientsPath = "${labPath}/clients-${hostName}.nix";

  cpmLib = inputs.network-control-plane-model.libBySystem.${system};
  cpmBuilt = cpmLib.compileAndBuildFromPaths {
    inputPath = intentPath;
    inherit inventoryPath;
  };

  controlPlaneArtifact =
    let
      artifactDigest = builtins.hashString "sha256" (builtins.toJSON cpmBuilt);
    in
    {
      kind = "network-control-plane-artifact";
      artifactIdentity = artifactDigest;
      inherit artifactDigest;
      control_plane_model = cpmBuilt;
      authorityConflicts = [ ];
      provenance = {
        producer = "nixos/${hostName}";
        source = "network-control-plane-model";
      };
    };

  canonicalBundle = inputs.network-realization-model.lib.realize {
    input = controlPlaneArtifact;
    requestScope = {
      kind = "complete-artifact";
      identity = hostName;
    };
    rootLockIdentity = builtins.hashString "sha256" (builtins.readFile ../../../../flake.lock);
    producerRevision =
      inputs.network-realization-model.rev
        or inputs.network-realization-model.dirtyRev
        or "uncommitted";
  };
in
{
  imports = [
    (relativeRepo.module "library/10-vms/nixos-shell-vm/host-config-routers-without-network")
    profiles.nixos.network.router-vlan2-runtime-contract

    (inputs.network-renderer-nixos.libBySystem.${system}.renderer.canonical.hostModule {
      inherit hostName;
      bundle = canonicalBundle;
    })

    (inputs.network-renderer-access-endpoint-nixos.libBySystem.${system}.renderer.canonical.hostModule {
      inherit hostName labSource;

      bundle = canonicalBundle;
      inventory = inventoryPath;
      clients = clientsPath;
      sops = "${labPath}/sops-routing-${hostName}.nix";
    })
  ];

  # Dedicated test fixture: request a real DHCP lease from the access-local
  # Kea server and put the client on the same access segment as the lab
  # clients. This belongs on s-router-test-clients, not on the router host.
  options.sRouterTestClientsDhcpClient.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Run the lab DHCP test client on the access-local bridge";
  };

  config = lib.mkIf config.sRouterTestClientsDhcpClient.enable {
    containers.dhcp-test = {
      autoStart = true;
      privateNetwork = true;
      hostBridge = "dns545nl";
      config = {
        system.stateVersion = "26.05";
        networking.useHostResolvConf = false;
        services.resolved.enable = true;
        systemd.network.enable = true;
        systemd.network.networks."10-eth0" = {
          matchConfig.Name = "eth0";
          networkConfig.DHCP = "ipv4";
          dhcpV4Config.UseDNS = false;
        };
      };
    };
  };
}
