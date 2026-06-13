{ inputs
, lib
, system
, hostName
, cpm
,
}:

{ ... }:

{
  imports = [
    # Nixos renderer: REQUIRES pre-compiled CPM (throws if cpm is null).
    (inputs.network-renderer-nixos.libBySystem.${system}.renderer.hostModule {
      inherit hostName;
      inherit cpm;
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
