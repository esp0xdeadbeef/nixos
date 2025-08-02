{ config, pkgs, lib, ... }:
{
  # Allow proprietary NVIDIA drivers
  nixpkgs.config.allowUnfree = true;

  # Prevent NVIDIA modules from auto-loading unexpectedly
  boot.blacklistedKernelModules = [
    "nvidia"
    "nvidia_modeset"
    "nvidia_uvm"
    "nvidia_drm"
  ];

  # Ensure modules are built into the initrd and available on-demand
  boot.initrd.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.nvidiaPackages.stable ];

  # One-shot systemd service to load NVIDIA modules on demand
  systemd.services.load-nvidia = {
    description = "Load NVIDIA kernel modules on demand";
    wantedBy    = [ "multi-user.target" ];
    serviceConfig = {
      Type      = "oneshot";
      # Load each module separately to avoid parameter confusion
      ExecStart = "${pkgs.bash}/bin/bash -c '
        ${pkgs.kmod}/bin/modprobe nvidia && \
        ${pkgs.kmod}/bin/modprobe nvidia_modeset && \
        ${pkgs.kmod}/bin/modprobe nvidia_uvm && \
        ${pkgs.kmod}/bin/modprobe nvidia_drm && \
        nvidia-modprobe || true
      '";
    };
  };

  # NVIDIA driver package and PRIME configuration
  hardware.nvidia = {
    package        = config.boot.kernelPackages.nvidiaPackages.stable;
    nvidiaSettings = true;
    prime = {
      intelBusId  = "PCI:00:02:0";
      nvidiaBusId = "PCI:01:00:0";
    };
  };

  # Install CUDA toolkit and user-land tools (nvidia-smi, settings)
  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
    (config.boot.kernelPackages).nvidia_x11
  ];

  # X server: boot with Intel, configure NVIDIA headlessly
  services.xserver = {
    enable       = true;
    videoDrivers = [ "i915" ];
    extraConfig  = ''
      Section "Device"
        Identifier "NvidiaDevice"
        Driver     "nvidia"
        Option     "UseDisplayDevice" "none"
        Option     "ConnectedMonitor"    "none"
        Option     "AllowEmptyInitialConfiguration"    "True"
      EndSection

      Section "ServerFlags"
        Option "AutoAddGPU" "off"
      EndSection
    '';
  };

  # Enable 32-bit OpenGL libraries
  hardware.graphics = { enable = true; enable32Bit = true; };

  # Docker with NVIDIA container runtime support
  virtualisation.docker = {
    enable       = true;
    enableOnBoot = true;
    package      = pkgs.docker;
    extraOptions = ''
      --add-runtime=nvidia=/run/nvidia/driver
    '';
  };
}
