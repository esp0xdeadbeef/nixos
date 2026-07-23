{ config
, lib
, pkgs
, ...
}:

let
  cfg = config.local.llm.ollamaSmokeTest;
  ollama = config.services.ollama;
  connectHost =
    if lib.elem ollama.host [
      "0.0.0.0"
      "::"
      "[::]"
    ]
    then "127.0.0.1"
    else ollama.host;
  baseUrl = "http://${connectHost}:${toString ollama.port}";
in
{
  options.local.llm.ollamaSmokeTest = {
    enable = lib.mkEnableOption "GPU inference smoke test for the configured Ollama service";

    model = lib.mkOption {
      type = lib.types.str;
      default = "deepseek-r1:8b";
      description = "Small model used to verify Ollama GPU inference.";
    };

    pullModel = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Pull the smoke-test model before inference.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = ollama.enable;
        message = "The Ollama smoke test requires services.ollama.enable.";
      }
    ];

    systemd.services.ollama-smoke-test = {
      description = "Verify Ollama GPU inference";
      wantedBy = [ "multi-user.target" ];
      after = [ "ollama.service" ];
      requires = [ "ollama.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "30s";
        TimeoutStartSec = "20min";
      };
      script = ''
        set -euo pipefail

        for _ in {1..120}; do
          if ${pkgs.curl}/bin/curl --fail --silent --show-error \
            ${lib.escapeShellArg "${baseUrl}/api/version"} >/dev/null; then
            ready=true
            break
          fi
          ${pkgs.coreutils}/bin/sleep 2
        done
        if [[ "''${ready:-false}" != true ]]; then
          echo "Ollama did not become ready at ${baseUrl}" >&2
          exit 1
        fi

        ${lib.optionalString cfg.pullModel ''
          pull_payload=$(${pkgs.jq}/bin/jq -cn \
            --arg model ${lib.escapeShellArg cfg.model} \
            '{ model: $model, stream: false }')

          ${pkgs.curl}/bin/curl --fail --silent --show-error \
            --max-time 1200 \
            --header 'Content-Type: application/json' \
            --data "$pull_payload" \
            ${lib.escapeShellArg "${baseUrl}/api/pull"} >/dev/null
        ''}

        payload=$(${pkgs.jq}/bin/jq -cn \
          --arg model ${lib.escapeShellArg cfg.model} \
          '{
            model: $model,
            prompt: "Reply only with OK",
            stream: false,
            keep_alive: "30s",
            options: { num_predict: 4 }
          }')

        ${pkgs.curl}/bin/curl --fail --silent --show-error \
          --max-time 300 \
          --header 'Content-Type: application/json' \
          --data "$payload" \
          ${lib.escapeShellArg "${baseUrl}/api/generate"} \
          | ${pkgs.jq}/bin/jq -e '.done == true' >/dev/null

        ${pkgs.curl}/bin/curl --fail --silent --show-error \
          ${lib.escapeShellArg "${baseUrl}/api/ps"} \
          | ${pkgs.jq}/bin/jq -e \
            '.models | any((.size_vram // 0) > 0)' >/dev/null

        unload_payload=$(${pkgs.jq}/bin/jq -cn \
          --arg model ${lib.escapeShellArg cfg.model} \
          '{ model: $model, keep_alive: 0 }')

        ${pkgs.curl}/bin/curl --fail --silent --show-error \
          --header 'Content-Type: application/json' \
          --data "$unload_payload" \
          ${lib.escapeShellArg "${baseUrl}/api/generate"} >/dev/null
      '';
    };
  };
}
