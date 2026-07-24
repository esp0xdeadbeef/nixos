{ inputs
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

  _module.args.sRouterTestClientsRenderers = {
    inherit canonicalBundle controlPlaneArtifact;
    cpm = cpmBuilt;
  };
}
