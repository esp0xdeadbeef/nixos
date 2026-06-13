{ inputs
, lib
, outPath
, ...
}:
let
  system = "x86_64-linux";
  labSource = "active-lab";
  hostName = "s-router-clab";

  cpmResult = inputs.network-control-plane-model.libBySystem.${system}.compileAndBuildFromPaths {
    inputPath = "${inputs.network-labs}/${labSource}/intent.nix";
    inventoryPath = "${inputs.network-labs}/${labSource}/inventory-clab.nix";
  };
in
{
  _module.args.sRouterClabLabProfile = {
    inherit labSource;
    labSelector = "s-router-clab";
  };

  networking.hostName = lib.mkForce "s-router-clab";

  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ./management-vlan2.nix

    (import ./renderers.nix {
      inherit inputs lib system hostName;
      cpm = cpmResult.control_plane_model;
      cpmResult = cpmResult;
    })
  ];
}
