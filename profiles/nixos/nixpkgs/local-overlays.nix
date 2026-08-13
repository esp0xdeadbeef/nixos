{ outputs, ... }:
{
  nixpkgs.overlays = [
    outputs.overlays.additions
    outputs.overlays.modifications
    outputs.overlays.unstable-packages
    outputs.overlays.nixpkgs-25_11-packages
    outputs.overlays.angr-nixpkgs-25_11-overwrite
  ];
}
