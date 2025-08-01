{
  pkgs,
  config,
  lib,
  ...
}:
{
  # services.xserver.videoDrivers = [ "nvidia" ];
  # hardware.nvidia = {
  #   open = true;
  #   modesetting.enable = true;
  #   nvidiaSettings = true;
  #   prime = {
  #     sync.enable = false; # gpu always
  #     offload.enable = false; # gpu on demand
  #     #nvidiaBusId = "PCI:10:0:0"; #epgu
  #     nvidiaBusId = "PCI:1:0:0"; # dedicated gpu
  #     intelBusId = "PCI:0:2:0";
  #   };
  # };
  # environment.sessionVariables = {
  #   __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  #   GBM_BACKEND = "nvidia-drm";
  #   WLR_NO_HARDWARE_CURSORS = "1";
  #   WLR_RENDERER_ALLOW_SOFTWARE = "1";
  # };

  # # # required for external monitor usage on nvidia offload
  # # specialisation = {
  # #   external-display.configuration = {
  # #     system.nixos.tags = [ "external-display" ];
  # #     hardware.nvidia.prime.offload.enable = lib.mkForce false;
  # #     hardware.nvidia.powerManagement.enable = lib.mkForce false;
  # #   };
  # # };
}
