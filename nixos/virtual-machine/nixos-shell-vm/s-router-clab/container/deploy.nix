{ pkgs, ... }:
let
  s-router-clab-deploy = pkgs.writeShellScriptBin "s-router-clab-deploy" ''
    set -euo pipefail

    work_dir="''${1:-/run/s-router-clab/live-current}"

    test -d "$work_dir" || {
      echo "missing host-produced CLAB work directory: $work_dir" >&2
      exit 1
    }
    test -d "$work_dir/network-artifacts" || {
      echo "missing host-produced CLAB network artifacts: $work_dir/network-artifacts" >&2
      exit 1
    }
    test -s "$work_dir/fabric.no-overlay.clab.yml" || {
      echo "missing host-produced CLAB topology: $work_dir/fabric.no-overlay.clab.yml" >&2
      exit 1
    }
    test -s "$work_dir/setup-bridge-links.sh" || {
      echo "missing host-produced CLAB bridge setup: $work_dir/setup-bridge-links.sh" >&2
      exit 1
    }
    test -s "$work_dir/verify-containerlab-deploy.sh" || {
      echo "missing host-produced CLAB deploy verifier: $work_dir/verify-containerlab-deploy.sh" >&2
      exit 1
    }

    rm -rf /etc/network-artifacts
    ln -s "$work_dir/network-artifacts" /etc/network-artifacts

    containerlab destroy --all --cleanup --yes || true
    docker ps -aq --filter 'name=^clab-fabric-' | xargs -r docker rm -f
    bash "$work_dir/setup-bridge-links.sh"
    containerlab deploy -t "$work_dir/fabric.no-overlay.clab.yml" -d --reconfigure
    bash "$work_dir/verify-containerlab-deploy.sh"
  '';
in
{
  environment.systemPackages = [ s-router-clab-deploy ];
}
