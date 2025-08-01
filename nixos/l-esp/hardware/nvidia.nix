{
  pkgs,
  config,
  lib,
  ...
}:
{
  # nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
  ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  # services.xserver.enable = lib.mkDefault false;
  services.xserver.videoDrivers = [
    "nvidia"
  ];

  hardware = {
    nvidia-container-toolkit.enable = true;

    nvidia = {
      # datacenter.enable = true;
      open = true;
      package = config.boot.kernelPackages.nvidiaPackages.production;
      prime = {
        # reverseSync.enable = true;
        # sync.enable = true;
        intelBusId = "PCI:00:02:0"; # Intel GPU Bus ID
        nvidiaBusId = "PCI:01:00:0"; # NVIDIA GPU Bus ID
      };
    };
  };
  # specialisation.on-the-go.configuration = {
  #   system.nixos.tags = [ "on-the-go" ];
  #   hardware.nvidia.prime = {
  #     offload = {
  #       enable = lib.mkForce true;
  #       enableOffloadCmd = lib.mkForce true;
  #     };
  #     sync.enable = lib.mkForce false;    
  #   };
  # };

  # virtualisation.docker = {
  #   enable = true;
  #   enableOnBoot = true;
  #   package = pkgs.docker;
  # };
}
