{ inputs
, outPath
, ...
}:
let
  system = "x86_64-linux";
  labSource = "active-lab";
  hostName = "s-router-test-clients";

  cpmResult = inputs.network-control-plane-model.libBySystem.${system}.compileAndBuildFromPaths {
    inputPath = "${inputs.network-labs}/${labSource}/intent.nix";
    inventoryPath = "${inputs.network-labs}/${labSource}/inventory-nixos.nix";
  };
in
{
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"

    # RENDERER_GAP: access-endpoint-nixos hostModule compiles CPM internally
    # from intent/inventory paths and does not yet consume pre-compiled cpm.
    # Passing cpm here so the host is architecturally correct; the renderer
    # ignores it today and falls back to its internal compilation.
    (inputs.network-renderer-access-endpoint-nixos.libBySystem.${system}.renderer.hostModule {
      inherit hostName labSource;
      cpm = cpmResult.control_plane_model;
    })

    ./management-vlan2.nix
  ];
}
