{ lib
, pkgsForRenderer
, modelHost
, siteName ? "hetz"
, endpointNames ? [ "hetz-client01" ]
,
}:
let
  clientBuilders = import ../../../nixos-shell-vm/s-router-test-clients/modules/client-builders.nix {
    inherit lib;
    pkgs = pkgsForRenderer;
  };
in
import ../../../nixos-shell-vm/s-router-test-clients/modules/model-site-clients.nix {
  inherit lib endpointNames siteName;
  pkgs = pkgsForRenderer;
  builders = clientBuilders;
  intent = import modelHost.fabric.intentPath;
  inventory = import modelHost.fabric.inventoryPath;
  runtimeTargets = modelHost.builtHost.runtimeTargets or { };
}
