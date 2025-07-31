{
  pkgs,
  config,
  libs,
  ...
}:
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
