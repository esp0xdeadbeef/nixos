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
    test -s "$work_dir/fabric.clab.yml" || {
      echo "missing host-produced CLAB topology: $work_dir/fabric.clab.yml" >&2
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

    renderer_repo="''${CLAB_RENDERER_REPO:-/run/s-router-clab/inputs/network-renderer-containerlab-linux-backend}"
    tooling_build="$renderer_repo/docker-clab-frr-plus-tooling/build.sh"
    test -x "$tooling_build" || {
      echo "missing CLAB FRR tooling image builder: $tooling_build" >&2
      exit 1
    }
    "$tooling_build"

    containerlab destroy --all --cleanup --yes || true
    docker ps -aq --filter 'name=^clab-fabric-' | xargs -r docker rm -f
    bash "$work_dir/setup-bridge-links.sh"
    containerlab deploy -t "$work_dir/fabric.clab.yml" --reconfigure
    bash "$work_dir/verify-containerlab-deploy.sh"
  '';
in
{
  environment.systemPackages = [ s-router-clab-deploy ];

  systemd.services.s-router-clab-deploy-live-boot = {
    description = "Deploy the last rendered s-router Containerlab topology";
    wantedBy = [ "multi-user.target" ];
    after = [
      "docker.service"
      "network-online.target"
    ];
    wants = [
      "docker.service"
      "network-online.target"
    ];
    path = [
      pkgs.bash
      pkgs.containerlab
      pkgs.coreutils
      pkgs.docker
      pkgs.findutils
      pkgs.gawk
      pkgs.iproute2
    ];
    unitConfig.ConditionPathExists = "/persist/s-router-clab/live-boot/fabric.clab.yml";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "10min";
    };
    script = ''
      exec ${s-router-clab-deploy}/bin/s-router-clab-deploy /persist/s-router-clab/live-boot
    '';
  };
}
