{ inputs
, ...
}:

let
  system = "x86_64-linux";
  labSource = "active-lab";

  cpm = inputs.network-control-plane-model.libBySystem.${system};
  labPath = "${inputs.network-labs}/${labSource}";
in
{
  imports = [
    (cpm.clientFixtures.hostModuleFromPaths {
      intentPath = "${labPath}/intent.nix";
      inventoryPath = "${labPath}/inventory-nixos.nix";
      sopsPath = "${labPath}/sops.nix";

      fixture = {
        kind = "emulated-clients";
        hostName = "s-router-test-clients";
        siteName = "nixos";
      };
    })
    (cpm.clientFixtures.hostModuleFromPaths {
      intentPath = "${labPath}/intent.nix";
      inventoryPath = "${labPath}/inventory-clab.nix";
      sopsPath = "${labPath}/sops.nix";

      fixture = {
        kind = "emulated-clients";
        hostName = "s-router-test-clients";
        siteName = "nixos";
      };
    })
  ];
}
