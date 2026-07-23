{ lib
, pkgs
, profiles
, ...
}:

let
  defaultModel = "deepseek-r1:8b";
  ollamaPackage = pkgs.unstable.ollama-cuda;

  benchmark = pkgs.writeShellApplication {
    name = "s-llm-inference-benchmark";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.gnugrep
      pkgs.jq
    ];
    text = ''
      set -euo pipefail

      model=''${1:-${lib.escapeShellArg defaultModel}}
      result=$(mktemp)
      hashcat_result=$(mktemp)
      trap 'rm -f "$result" "$hashcat_result"' EXIT

      benchmark_ollama() {
        local label=$1
        local port=$2
        local payload
        local tokens_per_second

        payload=$(jq -cn \
          --arg model "$model" \
          '{
            model: $model,
            prompt: "In one short paragraph, explain why deterministic benchmarks matter.",
            stream: false,
            keep_alive: "10m",
            options: { num_predict: 64, temperature: 0 }
          }')

        curl --fail --silent --show-error \
          --max-time 300 \
          --header 'Content-Type: application/json' \
          --data "$payload" \
          "http://127.0.0.1:$port/api/generate" > "$result"

        jq -e '.done == true and (.eval_count // 0) > 0 and (.eval_duration // 0) > 0' \
          "$result" >/dev/null
        tokens_per_second=$(jq -r \
          '((.eval_count * 1000000000 / .eval_duration) * 100 | round) / 100' \
          "$result")

        curl --fail --silent --show-error \
          "http://127.0.0.1:$port/api/ps" \
          | jq -e --arg model "$model" \
            '.models | any(.name == $model and (.size_vram // 0) > 0)' >/dev/null

        printf '%s: model=%s eval_tokens=%s eval_tokens_per_second=%s gpu_offload=yes\n' \
          "$label" \
          "$model" \
          "$(jq -r '.eval_count' "$result")" \
          "$tokens_per_second"
      }

      /run/current-system/sw/bin/nvidia-smi \
        --query-gpu=name,memory.total,driver_version \
        --format=csv,noheader

      benchmark_ollama native 11434
      benchmark_ollama podman 11435

      /run/current-system/sw/bin/hashcat -I \
        | grep --fixed-strings 'Tesla P100' >/dev/null
      /run/current-system/sw/bin/hashcat \
        --benchmark \
        --hash-type 0 \
        --workload-profile 2 \
        2>&1 | tee "$hashcat_result"
      grep --extended-regexp 'Speed\..*H/s' "$hashcat_result" >/dev/null
    '';
  };
in
{
  assertions = [
    {
      assertion = lib.elem defaultModel profiles.nixos.llm.model-sets.workstation;
      message = "The s-llm-inference benchmark model must be part of the workstation model set.";
    }
  ];

  environment.systemPackages = [ benchmark ];
}
