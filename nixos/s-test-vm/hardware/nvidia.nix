{
  pkgs,
  config,
  libs,
  ...
}:

{
  hardware.graphics.enable = true;

  # Use bochs or QEMU display (not NVIDIA)
  services.xserver.videoDrivers = [ "bochs" ];

  hardware.nvidia = {
    modesetting.enable = false; # not for display
    powerManagement.enable = false; # don't send ioctl signals to the powermanager
    powerManagement.finegrained = false;
    open = false;  # Use proprietary driver
    nvidiaSettings = false;  # You don't need the GUI settings tool
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
