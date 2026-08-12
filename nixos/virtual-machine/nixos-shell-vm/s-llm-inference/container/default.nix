{ config
, lib
, pkgs
, profiles
, relativeRepo
, ...
}:

let
  containerName = "${config.networking.hostName}-container";
  containerService = "container@${containerName}";
  hostStatePath = "/var/lib/private/ollama";
  hostModelsPath = "${hostStatePath}/models";
  ollamaPackage = pkgs.ollamaForHost;
  nvidiaPackage = config.hardware.nvidia.package;
  nvidiaDevices = [
    "/dev/nvidia0"
    "/dev/nvidiactl"
    "/dev/nvidia-modeset"
    "/dev/nvidia-uvm"
    "/dev/nvidia-uvm-tools"
  ];
in
{
  containers.${containerName} = {
    autoStart = true;
    ephemeral = true;
    privateNetwork = true;
    timeoutStartSec = "5min";

    # Match the s-test container networking pattern: the VM owns the VLAN
    # bridge and the container receives one private veth on that bridge.
    extraVeths.veth3.hostBridge = "vlan3";

    allowedDevices = map
      (node: {
        inherit node;
        modifier = "rw";
      })
      [
        "char-nvidia-caps"
        "char-nvidia-frontend"
        "char-nvidia-uvm"
        "char-nvidiactl"
      ];

    bindMounts =
      lib.genAttrs nvidiaDevices
        (hostPath: {
          inherit hostPath;
          isReadOnly = false;
        })
      // {
        "/dev/nvidia-caps" = {
          hostPath = "/dev/nvidia-caps";
          isReadOnly = false;
        };
        "/run/opengl-driver" = {
          hostPath = "/run/opengl-driver";
          isReadOnly = true;
        };
        # Match the host impermanence layout by sharing the complete Ollama
        # StateDirectory. A nested mount on models prevents systemd from
        # creating the service's state mount.
        "/var/lib/private/ollama" = {
          hostPath = hostStatePath;
          isReadOnly = false;
        };
      };

    config = {
      imports = [
        (relativeRepo.module "profiles/nixos/containers/nixos-container")
        (relativeRepo.module "library/01-general/password-cracking/default.nix")
        profiles.nixos.llm.ollama-gpu-ready
        profiles.nixos.llm.ollama-smoke-test
        ./network.nix
        ../ollama-state.nix
      ];

      nixpkgs.config = {
        inherit (config.nixpkgs.config) cudaCapabilities cudaForwardCompat;
      };

      services.ollama = {
        enable = true;
        package = ollamaPackage;
        models = "/var/lib/ollama/models";
        host = "0.0.0.0";
        port = 11434;
        environmentVariables.OLLAMA_KEEP_ALIVE = "5m";
      };

      local.llm.ollamaSmokeTest.enable = true;
      networking.firewall.allowedTCPPorts = [ 11434 ];

      environment.systemPackages = [
        ollamaPackage
        nvidiaPackage.bin
        pkgs.curl
      ];
    };
  };

  systemd.services.${containerService} = {
    after = [
      "nvidia-persistenced.service"
      "ollama.service"
    ];
    wants = [
      "nvidia-persistenced.service"
      "ollama.service"
    ];
    preStart = lib.mkBefore ''
      for _ in {1..60}; do
        if [[
          -d ${lib.escapeShellArg hostModelsPath}
          && -d /dev/nvidia-caps
          && -e /dev/nvidiactl
          && -e /dev/nvidia-uvm
        ]] && ${nvidiaPackage.bin}/bin/nvidia-smi \
            --query-gpu=uuid \
            --format=csv,noheader >/dev/null 2>&1; then
          runtime_ready=true
          break
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done
      if [[ "''${runtime_ready:-false}" != true ]]; then
        echo "Ollama model store or NVIDIA device nodes did not become ready" >&2
        exit 1
      fi
    '';
  };
}
