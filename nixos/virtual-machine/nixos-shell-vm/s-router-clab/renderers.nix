{ inputs
, lib
, system
, hostName
, cpm
, cpmResult
,
}:

{ pkgs, ... }:

let
  # Pre-built CPM as JSON for the containerlab renderer.
  cpmJson = pkgs.writeText "cpm.json" (builtins.toJSON cpmResult);
in
{
  imports = [
    # Containerlab: consumes pre-built CPM JSON.
    # RENDERER_GAP: rendererInventoryJsonPath not passed — the renderer should
    # extract what it needs from CPM output rather than requiring a separate
    # inventory JSON artifact.
    (inputs.network-renderer-containerlab-linux-backend.libBySystem.${system}.renderer.hostModule {
      inherit hostName;
      cpmJsonPath = "${cpmJson}";
    })

    # Nebula: RENDERER_GAP — hostModule requires intent/inventory paths and
    # compiles CPM internally. Passing cpm here; the renderer does not yet
    # consume it. See nebula flake.nix line 54.
    (inputs.network-renderer-nebula.libBySystem.${system}.renderer.hostModule {
      inherit hostName;
      inherit cpm;
    })

    # Wireguard: accepts pre-compiled CPM output.
    # CPM_GAP: wgInventory not passed — the renderer's buildWireGuardNodeConfigs
    # requires wgInventory keyed by overlay name. This data should be emitted by
    # CPM so the host does not need to walk inventory to extract it.
    (inputs.network-renderer-wireguard.libBySystem.${system}.renderer.hostModule {
      inherit hostName;
      controlPlaneModel = cpm;
    })
  ];
}
