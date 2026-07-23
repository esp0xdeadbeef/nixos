{ config, lib, pkgs, ... }:

{
  assertions = [
    {
      assertion = config.services.ollama.enable;
      message = "Ollama GPU readiness requires services.ollama.enable.";
    }
  ];

  systemd.services = {
    # Keep GPU probing outside ollama.service. With late PCI hotplug, starting
    # Ollama too early can materialize its device cgroup before the NVIDIA
    # character-device majors exist. A later retry inside that same cgroup
    # would then keep failing even after the GPU becomes usable.
    ollama-gpu-ready = {
      description = "Wait for the NVIDIA GPU used by Ollama";
      before = [ "ollama.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "5min";
      };
      script = ''
        gpu_ready=false
        for _attempt in $(${pkgs.coreutils}/bin/seq 1 1200); do
          if /run/current-system/sw/bin/nvidia-smi \
            --query-gpu=uuid \
            --format=csv,noheader >/dev/null 2>&1; then
            gpu_ready=true
            break
          fi
          ${pkgs.coreutils}/bin/sleep 0.25
        done

        if [[ "$gpu_ready" != true ]]; then
          echo "NVIDIA GPU did not become ready for Ollama" >&2
          exit 1
        fi
      '';
    };

    # Ollama discovers accelerators only during process startup.
    ollama = {
      after = [ "ollama-gpu-ready.service" ];
      requires = [ "ollama-gpu-ready.service" ];
    };
  };
}
