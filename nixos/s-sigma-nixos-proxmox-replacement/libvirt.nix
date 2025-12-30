{pkgs, ... }:
{
  virtualisation.libvirtd = {
    enable = true;
    onShutdown = "shutdown";  # Change from default "suspend" to "shutdown"【5】【6】
    parallelShutdown = 4;
    # shutdownTimeout = 120; default 300
  };
}
