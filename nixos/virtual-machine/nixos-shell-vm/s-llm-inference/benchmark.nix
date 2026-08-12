{ lib
, pkgs
, profiles
, ...
}:

let
  defaultModel = "deepseek-r1:8b";
  ollamaPackage = pkgs.ollama-cuda;

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

      ollama_curl() {
        local instance=$1
        local endpoint=$2
        shift 2

        if [[ "$instance" == host ]]; then
          curl "$@" "http://127.0.0.1:11434/$endpoint"
        else
          /run/current-system/sw/bin/nixos-container run s-llm-inference-container -- \
            /run/current-system/sw/bin/curl \
            "$@" "http://127.0.0.1:11434/$endpoint"
        fi
      }

      stop_model() {
        local instance=$1
        if [[ "$instance" == host ]]; then
          OLLAMA_HOST=127.0.0.1:11434 \
            ${lib.getExe ollamaPackage} stop "$model"
        else
          /run/current-system/sw/bin/nixos-container run s-llm-inference-container -- \
            /run/current-system/sw/bin/env \
            OLLAMA_HOST=127.0.0.1:11434 \
            ${lib.getExe ollamaPackage} stop "$model"
        fi
      }

      benchmark_ollama() {
        local instance=$1
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

        ollama_curl "$instance" api/generate \
          --fail --silent --show-error \
          --max-time 300 \
          --header 'Content-Type: application/json' \
          --data "$payload" > "$result"

        jq -e '.done == true and (.eval_count // 0) > 0 and (.eval_duration // 0) > 0' \
          "$result" >/dev/null
        tokens_per_second=$(jq -r \
          '((.eval_count * 1000000000 / .eval_duration) * 100 | round) / 100' \
          "$result")

        ollama_curl "$instance" api/ps \
          --fail --silent --show-error \
          | jq -e --arg model "$model" \
            '.models | any(.name == $model and (.size_vram // 0) > 0)' >/dev/null

        printf '%s: model=%s eval_tokens=%s eval_tokens_per_second=%s gpu_offload=yes\n' \
          "$instance" \
          "$model" \
          "$(jq -r '.eval_count' "$result")" \
          "$tokens_per_second"

        stop_model "$instance"
        sleep 2
      }

      /run/current-system/sw/bin/nvidia-smi \
        --query-gpu=name,memory.total,driver_version \
        --format=csv,noheader

      benchmark_ollama host
      benchmark_ollama container

      /run/current-system/sw/bin/nvidia-smi \
        --query-gpu=uuid \
        --format=csv,noheader \
        | grep --extended-regexp '^GPU-' >/dev/null
      /run/current-system/sw/bin/hashcat -I 2>&1 \
        | grep --fixed-strings 'CUDA Info:' >/dev/null
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
