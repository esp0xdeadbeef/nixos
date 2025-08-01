{
  pkgs,
  config,
  libs,
  ...
}:
<<<<<<< HEAD
{
  # nixpkgs.config.allowUnfree = true;
  # hardware.nvidia-container-toolkit.enable = true;

  # environment.systemPackages = with pkgs; [
  #   cudaPackages.cudatoolkit
  # ];

  # hardware.graphics = {
  #   enable = true;
  #   enable32Bit = true;
  # };

  # services.xserver.videoDrivers = [ "i915" ];

  # hardware.nvidia = {
  #   modesetting.enable = true;
  #   powerManagement.enable = false;
  #   open = false;
  #   nvidiaSettings = true;
  #   package = config.boot.kernelPackages.nvidiaPackages.stable;
  #   prime = {
  #     offload = {
  #       enable = true;
  #       enableOffloadCmd = true;
  #     };
  #     intelBusId = "PCI:0:2:0";
  #     nvidiaBusId = "PCI:1:0:0";
  #   };
  # };

  # virtualisation.docker = {
  #   enable = true;
  #   enableOnBoot = true;
  #   package = pkgs.docker;
  # };
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
