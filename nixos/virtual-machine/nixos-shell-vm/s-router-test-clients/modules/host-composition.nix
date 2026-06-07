{ inputs
, lib
, ...
}:

let
  system = "x86_64-linux";
  labSource = "active-lab";

  cpm = inputs.network-control-plane-model.libBySystem.${system};
  labPath = "${inputs.network-labs}/${labSource}";

  fixture = {
    kind = "emulated-clients";
    hostName = "s-router-test-clients";
    siteName = "nixos";
  };

  hostModuleFromInventory = inventoryPath:
    cpm.clientFixtures.hostModuleFromPaths {
      intentPath = "${labPath}/intent.nix";
      inherit inventoryPath;
      sopsPath = "${labPath}/sops.nix";

      inherit fixture;
    };

  nixosHostModule = hostModuleFromInventory "${labPath}/inventory-nixos.nix";
  clabHostModule = hostModuleFromInventory "${labPath}/inventory-clab.nix";

  renderedHostNetwork =
    (nixosHostModule._module.args.renderedHostNetwork or { })
    // (clabHostModule._module.args.renderedHostNetwork or { });

  stripRenderedHostNetworkArg = module:
    module // {
      _module = (module._module or { }) // {
        args = removeAttrs (module._module.args or { }) [
          "renderedHostNetwork"
        ];
      };
    };
in
lib.mkMerge [
  {
    _module.args.renderedHostNetwork = renderedHostNetwork;
  }
  (stripRenderedHostNetworkArg nixosHostModule)
  (stripRenderedHostNetworkArg clabHostModule)
]
