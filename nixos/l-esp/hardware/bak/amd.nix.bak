{ config, pkgs, ... }:
{
  services.xserver.videoDrivers = [ "amdgpu" "kfd" ];
  environment.systemPackages = with pkgs; [
    rocmPackages.rocm-smi
    rocmPackages.rocminfo
  ];
  # still whihing that the vid card is "insecure":
  # boot.kernelParams = [
  #   "amdgpu.secure_display=0"
  # ];
  services.supergfxd.enable = true;
  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
    };

    amdgpu.amdvlk = {
      enable = true;
      support32Bit.enable = true;
    };
  };
}
