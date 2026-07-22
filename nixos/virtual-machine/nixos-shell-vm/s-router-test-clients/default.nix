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
in
{
  imports = [
    (relativeRepo.module "library/10-vms/nixos-shell-vm/host-config-routers-without-network")
    profiles.nixos.network.router-vlan2-runtime-contract

    (inputs.network-renderer-nixos.libBySystem.${system}.renderer.hostModule {
      inherit hostName;
      cpm = cpmBuilt;
      controlPlane = cpmBuilt;
    })

    (inputs.network-renderer-access-endpoint-nixos.libBySystem.${system}.renderer.hostModule {
      inherit hostName labSource;

      cpm = cpmBuilt;
      controlPlane = cpmBuilt;
      inventory = inventoryPath;
      clients = clientsPath;
      sops = "${labPath}/sops-routing-${hostName}.nix";
    })
  ];
}
