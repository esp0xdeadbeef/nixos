#!/usr/bin/env bash
# Per-stage timing for the compiler -> NFM -> CPM -> realization -> renderer
# chain, for one router host.
#
# FS-940 defines a single end-to-end semantic-compile objective. It does not
# say WHICH stage consumes the budget, and one total hides a stage that
# dominates it. This harness times each hop separately so an optimisation has
# a before/after it can be judged by.
#
# Each stage runs in its own `nix eval`: one combined expression lets the
# evaluator share thunks across stages and reports a number no individual
# consumer would see. Best-of-N is reported, because the minimum is the
# sample least contaminated by unrelated load on the machine.
#
# Usage:
#   ./bench-pipeline-stages.sh [host] [runs]
set -euo pipefail

host="${1:-s-router-cobalt-new}"
runs="${2:-3}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

prelude=$(cat <<EOF
  flake = builtins.getFlake "${repo_root}";
  invRaw = import ${repo_root}/prod-network/testing/inventory-cobalt.nix;
  inv = if builtins.isFunction invRaw then invRaw { hostName = "${host}"; } else invRaw;
  intentPath = ${repo_root}/prod-network/testing/intent-cobalt.nix;
  cpm = flake.inputs.network-control-plane-model.libBySystem.aarch64-linux.compileAndBuildFromPaths {
    inputPath = intentPath;
    inventoryPath = inv;
  };
  art = {
    kind = "network-control-plane-artifact";
    artifactIdentity = "bench";
    artifactDigest = "bench";
    control_plane_model = cpm;
    authorityConflicts = [ ];
    provenance = { producer = "bench"; source = "bench"; };
  };
  bundle = flake.inputs.network-realization-model.lib.realize {
    input = art;
    requestScope = { kind = "complete-artifact"; identity = "${host}"; };
    rootLockIdentity = "bench";
    producerRevision = "bench";
  };
EOF
)

# measure <label> <nix-expression-returning-a-string>
measure() {
  local label="$1" expr="$2" i start end elapsed best=""
  for i in $(seq 1 "$runs"); do
    start=$(date +%s%3N)
    if ! nix eval --impure --raw --expr "$expr" >/dev/null 2>&1; then
      printf '%s\tFAIL\t-\n' "$label"
      return 0
    fi
    end=$(date +%s%3N)
    elapsed=$((end - start))
    if [ -z "$best" ] || [ "$elapsed" -lt "$best" ]; then best="$elapsed"; fi
  done
  local bytes
  bytes=$(nix eval --impure --raw --expr "$expr" 2>/dev/null || echo "?")
  printf '%s\t%s\t%s\n' "$label" "$best" "$bytes"
}

echo "# host=${host} runs=${runs} date=$(date -Is)"
echo "# revision=$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo -e "stage\tbest_ms\tpayload_bytes"

measure "compiler-only" "
  let ${prelude}
  in toString (builtins.stringLength (builtins.toJSON
       (flake.inputs.network-compiler.lib.compile \"aarch64-linux\" (import intentPath))))"

measure "cpm(compiler+nfm+cpm)" "
  let ${prelude}
  in toString (builtins.stringLength (builtins.toJSON cpm))"

measure "bundle-full" "
  let ${prelude}
  in toString (builtins.stringLength (builtins.toJSON bundle))"

measure "bundle-network-only" "
  let ${prelude}
  in toString (builtins.stringLength (builtins.toJSON bundle.network))"

measure "bundle-upstream-coverage" "
  let ${prelude}
  in toString (builtins.stringLength (builtins.toJSON bundle.upstreamCoverage))"
