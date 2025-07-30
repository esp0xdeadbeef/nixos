{
  pkgs,
  config,
  libs,
  ...
}:

{
  environment.systemPackages = with pkgs; [
    config.boot.kernelPackages.nvidiaPackages.stable.bin
  ];
  # boot.initrd.kernelModules = [ "nvidia" ]; # THIS SHOULD BE ENABLED!!!

  boot.blacklistedKernelModules = [
    "amdgpu"
  #   "nouveau" # this fucks up the intel videocard.
  ];
  hardware.nvidia = {
    # modesetting.enable = true;
    # powerManagement.enable = false;
    # powerManagement.finegrained = true;
    open = true;
    # nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  nixpkgs.config.cudaSupport = true;

  virtualisation.docker.daemon.settings.features.cdi = true;
  virtualisation.docker.rootless.daemon.settings.features.cdi = true;
}