{ pkgs, ... }:

# Always-on network console for the board.
#
# Why: the serial console was only reachable through a USB-serial adapter on
# the operator's laptop. That adapter does not re-enumerate after a WARM reboot
# (VBUS is never cycled, so the device sees no power-on and the host gets no
# connect event) -- observed on 2026-11-09: the board kernel-panicked in
# mtk_eth, warm-rebooted, and the console stayed dead until a physical
# powercycle. A console that disappears exactly when the board crashes is
# useless for diagnosing a crash.
#
# So the board publishes its own ttyS0 over TCP, independent of any USB. It is
# enabled at boot, restarts forever, and keeps working across panics/reboots.
#
# Client side:   socat - TCP:100.64.0.18:7000
# Or in tio:     tio --socket ... (not needed; socat is enough)
{
  systemd.services."serial-console-tcp" = {
    description = "Expose the board serial console (ttyS0) over TCP";
    wantedBy = [ "multi-user.target" ];
    after = [ "dev-ttyS0.device" ];
    requires = [ "dev-ttyS0.device" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:7000,reuseaddr,fork,keepalive FILE:/dev/ttyS0,raw,echo=0,nonblock";
      Restart = "always";
      RestartSec = "2s";
      # Never let a wedged console take the host down.
      Nice = 5;
    };
  };

  networking.firewall.allowedTCPPorts = [ 7000 ];
}
