# hardware/amd-gpu-hashcat.nix
{ config, pkgs, ... }:

{
  #### Kernel/Driver Settings ####
  boot.kernelPackages = pkgs.linuxPackages_zen;  # use Zen kernel (with amdgpu fixes for APU stability)
  services.xserver.videoDrivers = [ "amdgpu" ];
  # Ensure amdgpu loads early (especially if no X):
  boot.initrd.kernelModules = [ "amdgpu" ];

  #### OpenCL/ROCm Configuration ####
  nixpkgs.config.rocmSupport = true;
  hardware.graphics.enable = true;
  hardware.graphics.extraPackages = with pkgs; [
    rocmPackages.clr.icd    # AMD ROCm OpenCL ICD for GPU (ROCm 5.x)
    pocl                    # POCL OpenCL for CPU
  ];
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
    HCC_AMDGPU_TARGET = "gfx1030";        # Target RDNA2 gfx1030 architecture (workaround):contentReference[oaicite:12]{index=12}
    # ROC_ENABLE_PRE_VEGA = "1";          # (Not needed for Vega – only for Polaris GCN4 cards:contentReference[oaicite:13]{index=13})
  };

  #### User Permissions ####
  users.users.deadbeef = {
    extraGroups = [ "video" "render" ];
    # ...other user settings...
  };

  

}
