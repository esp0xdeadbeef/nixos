# hardware/amd-gpu-hashcat.nix
{ config, pkgs, ... }:

{
  #### Kernel/Driver Settings ####
  boot.kernelPackages = pkgs.linuxPackages_zen; # use Zen kernel (with amdgpu fixes for APU stability)
  services.xserver.videoDrivers = [ "amdgpu" ];
  boot.kernelPatches = [
    {
      name = "amdgpu-stability-patch-zen";
      patch = pkgs.fetchpatch {
        name = "amdgpu-stability-patch-zen";
        url = "https://github.com/zen-kernel/zen-kernel/compare/fd00d197bb0a82b25e28d26d4937f917969012aa...WhiteHusky:zen-kernel:f4c32ca166ad55d7e2bbf9adf121113500f3b42b.diff";
        hash = "sha256-bMT5OqBCyILwspWJyZk0j0c8gbxtcsEI53cQMbhbkL8=";
      };
    }
  ];
  # Ensure amdgpu loads early (especially if no X):
  boot.initrd.kernelModules = [ "amdgpu" ];

  #### OpenCL/ROCm Configuration ####
  # nixpkgs.config.rocmSupport = true;
  # hardware.graphics.enable = true;
  # hardware.graphics.extraPackages = with pkgs; [
  #   rocmPackages.clr.icd # AMD ROCm OpenCL ICD for GPU (ROCm 5.x)
  #   pocl # POCL OpenCL for CPU
  # ];
  # If on NixOS release where rocmPackages is older than 5.7 and unstable has 5.7:
  # (Optional overlay to pull a newer ROCm)
  # hardware.opengl.extraPackages = with import <nixos-unstable> { config.allowUnfree = true; }; [
  #   rocmPackages_5_7.clr.icd
  #   pocl
  # ];

  #### Environment Variables for ROCm on unsupported iGPU ####
  environment.sessionVariables = {
    # HSA_NO_SCRATCH_RECLAIM = "1";         # (optional tweak to avoid KFD resets on APUs)
    # HSA_OVERRIDE_GFX_VERSION = "9.0.0";   # Pretend Vega iGPU is GFX9 (supported):contentReference[oaicite:11]{index=11}
    HCC_AMDGPU_TARGET = "gfx1030"; # Target RDNA2 gfx1030 architecture (workaround):contentReference[oaicite:12]{index=12}
    # ROC_ENABLE_PRE_VEGA = "1";          # (Not needed for Vega – only for Polaris GCN4 cards:contentReference[oaicite:13]{index=13})
  };

  #### User Permissions ####
  users.users.deadbeef = {
    extraGroups = [
      "video"
      "render"
    ];
    # ...other user settings...
  };
  boot.kernelParams = [ "amdgpu.vm_fragment_size=9" ];

  # services.xserver = {
  #   enable = true;
  #   videoDrivers = [ "amdgpu" ];
  # };

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      # rocmPackages.clr.icd
    rocmPackages.clr.icd # AMD ROCm OpenCL ICD for GPU (ROCm 5.x)
    pocl # POCL OpenCL for CPU
    ];
  };

  hardware.opengl.enable = true;
  nixpkgs.config.rocmSupport = true;
  hardware.opengl.extraPackages = with pkgs; [
    rocmPackages.clr.icd # ROCm OpenCL runtime (GPU)
    pocl # Portable OpenCL (CPU)
  ];

  environment.systemPackages = with pkgs; [
    clinfo
    pkgs.unstable.hashcat
    rocmPackages.rocm-smi
  ];

  environment.variables = {
    ROC_ENABLE_PRE_VEGA = "1";
    # HSA_OVERRIDE_GFX_VERSION = "10.3.0";
  };

  environment.etc."hashcat-wrapper" = {
    text = ''
      #!/bin/sh
      exec ${pkgs.hashcat}/bin/hashcat -D 1 "$@"
    '';
    mode = "0755";
  };
}
