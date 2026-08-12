{ inputs
, pkgs
, ...
}:

{
  imports = [
    inputs.nixos-hardware.nixosModules.common-cpu-intel
    inputs.nixos-hardware.nixosModules.common-gpu-intel
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd

  ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.nvidia = {
    open = false;
    modesetting.enable = true;
    nvidiaSettings = true;

    powerManagement.enable = true;
    powerManagement.finegrained = false;

    prime = {
      intelBusId = "PCI:00:02:0";
      nvidiaBusId = "PCI:01:00:0";

      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
    };
  };

  services.ollama.package = pkgs.ollama-cuda;

}
