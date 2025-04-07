{ config, pkgs, ... }:
{
  services.xserver.videoDrivers = [ "amdgpu" ];
  environment.systemPackages = with pkgs; [
    rocmPackages.rocm-smi
  ];
  # still whihing that the vid card is "insecure":
  # boot.kernelParams = [
  #   "amdgpu.secure_display=0"
  # ];
  services.supergfxd.enable = true;

}
