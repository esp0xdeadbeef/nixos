{ config, pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;

  # it does not seem to be required to be able to use hashcat with cuda on the work laptop. Disabling it now.
  # nixpkgs.config.cudaSupport = true;          # build hashcat with CUDA support

  # Use bochs for display; do not load nvidia DRM
  services.xserver.videoDrivers = [ "bochs" ];
  boot.blacklistedKernelModules = [ "nvidia_drm" "nvidia_modeset" ];

  # Enable OpenGL so /run/opengl-driver and OpenCL vendor files are created
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
    # Ensure our OpenCL vendor (nvidia) is available to the loader
    extraPackages = with pkgs; [ config.boot.kernelPackages.nvidia_x11 ];
  };

  # Install the NVIDIA user‑space driver and CUDA toolkit (for nvidia-smi and CUDA)
  boot.extraModulePackages = [ config.boot.kernelPackages.nvidia_x11 ];
  environment.systemPackages = with pkgs; [
    config.boot.kernelPackages.nvidia_x11
    cudaPackages.cudatoolkit
    hashcat
    glxinfo
    clinfo
  ];

  # Load only the compute modules (no DRM)
  boot.kernelModules = [ "nvidia" "nvidia_uvm" ];

  # Keep the desktop running on Mesa/bochs but provide the NVIDIA libs via OpenGL
  environment.sessionVariables = {
    # Point the ICD loader to the correct vendor directory
    OCL_ICD_VENDORS = "/run/opengl-driver/etc/OpenCL/vendors";
    __GLX_VENDOR_LIBRARY_NAME = "mesa";   # force mesa for GUI
  };
}
