{ lib, ... }:

{
  # The P100 is Pascal and therefore needs the closed 580 LTS kernel module.
  # The 590+ branches no longer support this GPU generation.
  # qemu-vm uses mkVMOverride (priority 10) to force modesetting. This guest
  # s-llm-inference has a physical NVIDIA device, so override that VM default.
  services.xserver.videoDrivers = lib.mkOverride 5 [ "nvidia" ];

  hardware.nvidia = {
    branch = "legacy_580";
    open = false;
    nvidiaPersistenced = true;
    nvidiaSettings = false;
  };

  # Generate a CDI specification so Podman can delegate the already passed
  # through GPU to the Ollama container without nested VFIO.
  hardware.nvidia-container-toolkit.enable = true;
}
