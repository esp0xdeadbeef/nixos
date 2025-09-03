{
  pkgs,
  config,
  libs,
  ...
}:

{
  hardware.graphics.enable = true;

  # Use bochs or QEMU display (not NVIDIA)
  services.xserver.videoDrivers = [ "bochs" "nvidia"  ];

  hardware.nvidia = {
    modesetting.enable = false;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    open = false;
    nvidiaSettings = true;
  };

  # boot.kernelModules = [ "nvidia" "nvidia_uvm" "nvidia_drm" ];
  # services.xserver.videoDrivers = [ "modesetting" ];  # or "bochs" if X is in VM
  # virtualisation.docker.enableNvidia = true;


  nixpkgs.config.cudaSupport = true;

  # For headless CUDA Docker containers
  virtualisation.docker.daemon.settings.features.cdi = true;
  virtualisation.docker.rootless.daemon.settings.features.cdi = true;

  # Optional: ensure nvidia driver is loaded (compute-only)
  boot.kernelModules = [ "nvidia" "nvidia_uvm" ];
}
