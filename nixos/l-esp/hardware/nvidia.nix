{
  pkgs,
  config,
  libs,
  ...
}:
{
  nixpkgs.config.allowUnfree = true;
  hardware.nvidia-container-toolkit.enable = true;

  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
  ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  services.xserver.enable = true;
  services.xserver.videoDrivers = [
    "nvidia"
  ];

  hardware.nvidia = {
    open = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    # prime = {
    #   sync.enable = true;
    #   intelBusId = "PCI:00:02:0"; # Intel GPU Bus ID
    #   nvidiaBusId = "PCI:01:00:0"; # NVIDIA GPU Bus ID
    # };
  };

  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    package = pkgs.docker;
  };
}
