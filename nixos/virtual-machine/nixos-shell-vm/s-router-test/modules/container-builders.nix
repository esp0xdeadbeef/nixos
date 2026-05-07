{ lib, pkgs, mkNebulaRuntimeService }:

let
  debugPackages = import ./container-debug-packages.nix { inherit pkgs; };

  tenantEndpoints = import ./tenant-endpoints.nix {
    inherit lib debugPackages;
  };

  dmzEndpoint = import ./dmz-endpoint.nix {
    inherit lib debugPackages;
  };

  nebulaContainers = import ./nebula-container-builders.nix {
    inherit debugPackages mkNebulaRuntimeService;
  };
in
tenantEndpoints // dmzEndpoint // nebulaContainers
