{ config, pkgs, ... }:
{
  services.xserver.videoDrivers = [ "amdgpu" ];
  environment.systemPackages = with pkgs; [
    rocmPackages.rocm-smi
  ];
  boot.kernelParams = [
    "amdgpu.secure_display=0"
  ];

}
