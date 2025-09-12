{ config, pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;

  # it does not seem to be required to be able to use hashcat with cuda on the work laptop. Disabling it now.
  nixpkgs.config.cudaSupport = true; # build hashcat with CUDA support

  # Use bochs for display; do not load nvidia DRM
  services.xserver.videoDrivers = [
    "bochs"
    "nvidia"
  ];
  # boot.blacklistedKernelModules = [ "nvidia_drm" "nvidia_modeset" ];
  hardware.graphics.enable = true;
  # hardware.graphics.extraPackages = with pkgs; [ config.boot.kernelPackages.nvidia_x11 ];
  # boot.extraModulePackages = [ config.boot.kernelPackages.nvidia_x11 ];
  boot.kernelModules = [
    "nvidia"
    "nvidia_uvm"
  ];
  hardware.opengl = {
    enable = true;
    # setLdLibraryPath = true;
    extraPackages = with pkgs; [ mesa ];
  };
  programs.ld-so.enable = true;


  hardware.nvidia.open = true;

  # Install the NVIDIA user‑space driver and CUDA toolkit (for nvidia-smi and CUDA)
  boot.extraModulePackages = [ config.boot.kernelPackages.nvidia_x11 ];
  environment.systemPackages = with pkgs; [
    config.boot.kernelPackages.nvidia_x11
    cudaPackages.cudatoolkit
    hashcat
    glxinfo
    clinfo
  ];

  # Keep the desktop running on Mesa/bochs but provide the NVIDIA libs via OpenGL
  environment.sessionVariables = {
    # Point the ICD loader to the correct vendor directory
    OCL_ICD_VENDORS = "/run/opengl-driver/etc/OpenCL/vendors";
    __GLX_VENDOR_LIBRARY_NAME = "mesa"; # force mesa for GUI
  };
  environment.etc."modprobe.d/nvidia.conf".text = ''
    options nvidia_drm modeset=0
  '';
  environment.etc."egl_vendor.d/00_nvidia.json".text = ''
    {
      "file_format_version": "1.0.0",
      "ICD": {
        "library_path": "DISABLED"
      }
    }
  '';

}
