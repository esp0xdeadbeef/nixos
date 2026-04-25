let
  repoRoot = ../../../../.;
  lock = builtins.fromJSON (builtins.readFile "${repoRoot}/flake.lock");
  locked = lock.nodes.network-labs.locked;
  flake =
    builtins.getFlake
      "github:${locked.owner}/${locked.repo}/${locked.rev}";
in
import "${flake.inputs.network-labs}/examples/tri-site-dual-wan-overlay-integration-bgp/intent.nix"
