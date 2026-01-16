{ config, pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.cudaSupport = true;

  # GUI stack on QEMU drivers
  services.xserver.videoDrivers = [ "bochs" ];

  # Mesa for GUI rendering
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ mesa ];
  };

  # NVIDIA kernel modules for compute only
  boot.kernelModules = [ "nvidia" "nvidia_uvm" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.nvidia_x11 ];

  hardware.nvidia.open = true;

  # Block DRM modeset so NVIDIA never takes display
  environment.etc."modprobe.d/nvidia.conf".text = ''
    options nvidia_drm modeset=0
  '';

  # Install NVIDIA userspace (for nvidia-smi, CUDA, OpenCL runtime)
  environment.systemPackages = with pkgs; [
    config.boot.kernelPackages.nvidia_x11
    cudaPackages.cudatoolkit
    hashcat
    glxinfo
    clinfo
  ];

  # Expose NVIDIA’s OpenCL ICD, but force Mesa for GL/EGL
  environment.etc."OpenCL/vendors/nvidia.icd".source =
    "${config.boot.kernelPackages.nvidia_x11}/etc/OpenCL/vendors/nvidia.icd";

  environment.sessionVariables = {
    __GLX_VENDOR_LIBRARY_NAME = "mesa";   # GL always Mesa
    OCL_ICD_VENDORS = "/etc/OpenCL/vendors"; # picks up NVIDIA ICD above
  };
}
