{ lib, ... }:

{
  # Install the NVIDIA userspace libraries under /run/opengl-driver. These are
  # also required by headless services such as nvidia-persistenced.
  hardware.graphics.enable = true;

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

  # The GPU is attached after boot, so keep retrying until the PCI device and
  # its driver nodes have appeared.
  systemd.services.nvidia-persistenced = {
    startLimitIntervalSec = 0;
    serviceConfig.RestartSec = "2s";
  };
}
