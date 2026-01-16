{pkgs, ... }:
{
  virtualisation.libvirtd = {
    enable = true;
    onShutdown = "shutdown";  # Change from default "suspend" to "shutdown"【5】【6】
    parallelShutdown = 4;
    # shutdownTimeout = 120; default 300
  };
boot.extraModprobeConfig = ''
    options kvm_intel nested=1
    options kvm_intel emulate_invalid_guest_state=0
    options kvm ignore_msrs=1
  '';

}
