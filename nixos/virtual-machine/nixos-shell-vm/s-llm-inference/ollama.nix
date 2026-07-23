{ lib
, pkgs
, profiles
, ...
}:

let
  ollamaPackage = pkgs.unstable.ollama-cuda;
  models = profiles.nixos.llm.model-sets.heavy;
  smokeTestModel = "deepseek-r1:8b";
  sharedModelsPath = "/var/lib/private/ollama/models";
  imageName = "localhost/s-llm-inference-ollama";
  imageTag = ollamaPackage.version;

  ollamaRoot = pkgs.buildEnv {
    name = "s-llm-inference-ollama-root";
    paths = [
      ollamaPackage
      pkgs.cacert
      pkgs.coreutils
    ];
    pathsToLink = [
      "/bin"
      "/etc/ssl/certs"
    ];
  };

  ollamaImage = pkgs.dockerTools.streamLayeredImage {
    name = imageName;
    tag = imageTag;
    contents = [ ollamaRoot ];
    config = {
      Entrypoint = [ "/bin/ollama" ];
      Cmd = [ "serve" ];
      Env = [
        "HOME=/var/lib/ollama"
        "OLLAMA_HOST=0.0.0.0:11435"
        "OLLAMA_MODELS=/var/lib/ollama/models"
        "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      ];
      WorkingDir = "/var/lib/ollama";
    };
  };
in
{
  services.ollama = {
    # ollama-base enables the service; this is the same CUDA package selection
    # used by l-esp and l-envil.
    package = ollamaPackage;
    host = "0.0.0.0";
    port = 11434;
    loadModels = models;
    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "5m";
    };
  };

  virtualisation = {
    podman.enable = true;
    oci-containers = {
      backend = "podman";
      containers.ollama-container = {
        image = "${imageName}:${imageTag}";
        imageStream = ollamaImage;
        autoStart = true;
        volumes = [
          "/persist/var/lib/ollama-container:/var/lib/ollama"
          "${sharedModelsPath}:/var/lib/ollama/models:ro"
        ];
        extraOptions = [
          "--device=nvidia.com/gpu=all"
          "--network=host"
        ];
      };
    };
  };

  systemd = {
    tmpfiles.rules = [
      "d /persist/var/lib/ollama-container 0755 root root -"
    ];

    services = {
      ollama = {
        after = [ "nvidia-persistenced.service" ];
        wants = [ "nvidia-persistenced.service" ];
      };

      # Native Ollama owns the shared model store and is the only service that
      # downloads models. Podman consumes the same store read-only.
      ollama-model-loader = {
        after = [ "ollama-smoke-test.service" ];
        requires = [ "ollama-smoke-test.service" ];
        script = lib.mkForce ''
          failed=0
          ${lib.concatMapStringsSep "\n" (model: ''
            if ! OLLAMA_HOST=127.0.0.1:11434 \
              ${lib.getExe ollamaPackage} pull ${lib.escapeShellArg model}; then
              echo "Failed to pull ${model}" >&2
              failed=1
            fi
          '') models}
          exit "$failed"
        '';
      };

      podman-ollama-container = {
        after = [ "nvidia-container-toolkit-cdi-generator.service" ];
        requires = [ "nvidia-container-toolkit-cdi-generator.service" ];
      };

      ollama-smoke-test = {
        description = "Verify native and containerized Ollama GPU inference";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
          "nvidia-persistenced.service"
          "ollama.service"
          "podman-ollama-container.service"
        ];
        wants = [ "network-online.target" ];
        requires = [
          "ollama.service"
          "podman-ollama-container.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "30s";
          TimeoutStartSec = "20min";
          Environment = [ "HOME=/var/lib/ollama" ];
        };
        script = ''
          set -euo pipefail

          wait_for_ollama() {
            local port=$1
            for _ in {1..120}; do
              if ${pkgs.curl}/bin/curl --fail --silent --show-error \
                "http://127.0.0.1:$port/api/version" >/dev/null; then
                return 0
              fi
              ${pkgs.coreutils}/bin/sleep 2
            done
            echo "Ollama on port $port did not become ready" >&2
            return 1
          }

          verify_gpu_inference() {
            local port=$1
            local payload
            payload=$(${pkgs.jq}/bin/jq -cn \
              --arg model ${lib.escapeShellArg smokeTestModel} \
              '{
                model: $model,
                prompt: "Reply only with OK",
                stream: false,
                keep_alive: "10m",
                options: { num_predict: 4 }
              }')

            ${pkgs.curl}/bin/curl --fail --silent --show-error \
              --max-time 300 \
              --header 'Content-Type: application/json' \
              --data "$payload" \
              "http://127.0.0.1:$port/api/generate" \
              | ${pkgs.jq}/bin/jq -e '.done == true' >/dev/null

            ${pkgs.curl}/bin/curl --fail --silent --show-error \
              "http://127.0.0.1:$port/api/ps" \
              | ${pkgs.jq}/bin/jq -e \
                '.models | any((.size_vram // 0) > 0)' >/dev/null
          }

          wait_for_ollama 11434
          wait_for_ollama 11435

          OLLAMA_HOST=127.0.0.1:11434 \
            ${lib.getExe ollamaPackage} pull ${lib.escapeShellArg smokeTestModel}

          verify_gpu_inference 11434
          verify_gpu_inference 11435

          /run/current-system/sw/bin/hashcat -I \
            | ${pkgs.gnugrep}/bin/grep --fixed-strings 'Tesla P100' >/dev/null
        '';
      };

    };
  };
}
