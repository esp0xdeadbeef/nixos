{
  pkgs,
  config,
  libs,
  ...
}:
<<<<<<< HEAD
{
  nixpkgs.config.allowUnfree = true;
  hardware.nvidia-container-toolkit.enable = true;

  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
  ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  services.xserver.enable = true;
  services.xserver.videoDrivers = [
    # "i915" # USE THIS....
    # "modesetting"
    "nvidia"
  ];
  # hardware.nvidia.datacenter.enable = true;
  # hardware.nvidia-container-toolkit.suppressNvidiaDriverAssertion = true;

  hardware.nvidia = {
    #   modesetting.enable = true;
    #   powerManagement.enable = false;
    open = true;
    #   nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    prime = {
      sync.enable = true;
      intelBusId = "PCI:00:02:0"; # Intel GPU Bus ID
      nvidiaBusId = "PCI:01:00:0"; # NVIDIA GPU Bus ID
    };
  };

  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    package = pkgs.docker;
  };
}
=======

{
  environment.systemPackages = with pkgs; [
    config.boot.kernelPackages.nvidiaPackages.stable.bin
  ];
  # boot.initrd.kernelModules = [ "nvidia" ]; # THIS SHOULD BE ENABLED!!!

  boot.blacklistedKernelModules = [
    "amdgpu"
  #   "nouveau" # this fucks up the intel videocard.
  ];
  hardware.nvidia = {
    # modesetting.enable = true;
    # powerManagement.enable = false;
    # powerManagement.finegrained = true;
    open = true;
    # nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  nixpkgs.config.cudaSupport = true;

  virtualisation.docker.daemon.settings.features.cdi = true;
  virtualisation.docker.rootless.daemon.settings.features.cdi = true;
}
>>>>>>> work-laptop-merge-base
