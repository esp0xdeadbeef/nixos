{
  config,
  pkgs,
  lib,
  ...
}:

{
  boot.initrd.kernelModules = [
    "i915"
    "nvidia"
  ];
  services.xserver.enable = false;
  services.xserver.displayManager.gdm.enable = false;
  services.displayManager.sddm.enable = false;
  services.xserver.videoDrivers = [
    "modesetting"
    "nvidia"
  ];
  hardware.nvidia = {
    open = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    modesetting.enable = true;
    prime = {
      sync.enable = false;
      offload.enable = false;
      nvidiaBusId = "PCI:1:0:0";
      intelBusId = "PCI:0:2:0";
    };
  };

  environment.variables = {
    WLR_DRM_DEVICES = "/dev/dri/card1:/dev/dri/card0";
    WLR_NO_HARDWARE_CURSORS = "1";
    WLR_RENDERER_ALLOW_SOFTWARE = "1";
  };

  environment.shellAliases = {
    sway = "sway --unsupported-gpu";
  };

  programs.sway.enable = true;
}
