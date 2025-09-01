{
  pkgs,
  config,
  libs,
  ...
}:

{
  hardware.graphics.enable = true;

  # Use bochs or QEMU display (not NVIDIA)
  # services.xserver.videoDrivers = [ "bochs" ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    open = false;
    nvidiaSettings = false;
    # containerToolkit.enable = true;  # For Docker CUDA support
  };

  # virtualisation.docker.enableNvidia = true;


  nixpkgs.config.cudaSupport = true;

  # For headless CUDA Docker containers
  virtualisation.docker.daemon.settings.features.cdi = true;
  virtualisation.docker.rootless.daemon.settings.features.cdi = true;

  # Optional: ensure nvidia driver is loaded (compute-only)
  boot.kernelModules = [ "nvidia" "nvidia_uvm" ];
}
