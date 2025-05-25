{ config, pkgs, ... }:

{
  boot.kernelPackages = pkgs.linuxPackages_zen;

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

  boot.initrd.kernelModules = [ "amdgpu" ];
  boot.kernelParams = [ "amdgpu.vm_fragment_size=9" ];

  services.xserver = {
    enable = true;
    videoDrivers = [ "amdgpu" ];
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
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
