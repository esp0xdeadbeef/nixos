{ inputs
, outPath
, ...
}:
let
  system = "x86_64-linux";
  labSource = "active-lab";
  hostName = "s-router-test-clients";

  cpmLib = inputs.network-control-plane-model.libBySystem.${system};
  cpmBuilt = cpmLib.compileAndBuildFromPaths {
    inputPath = "${inputs.network-labs}/${labSource}/intent.nix";
    inventoryPath = "${inputs.network-labs}/${labSource}/inventory-nixos.nix";
  };
in
{
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"

    (inputs.network-renderer-nixos.libBySystem.${system}.renderer.hostModule {
      inherit hostName;
      cpm = cpmBuilt;
      controlPlane = cpmBuilt;
    })

    (inputs.network-renderer-access-endpoint-nixos.libBySystem.${system}.renderer.hostModule {
      inherit hostName labSource;

      cpm = cpmBuilt;
      controlPlane = cpmBuilt;
      inventory = "${inputs.network-labs}/${labSource}/inventory-nixos.nix";
      clients = "${inputs.network-labs}/${labSource}/clients.nix";
      sops = "${inputs.network-labs}/${labSource}/sops-routing-${hostName}.nix";
    })
  ];
}
