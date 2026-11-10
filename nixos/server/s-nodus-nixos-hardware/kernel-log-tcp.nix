{ pkgs, ... }:

# Always-on kernel/console log stream, served by the board itself.
#
# Why not a TCP bridge on /dev/ttyS0: reading a serial tty returns only what
# arrives on RX. What the kernel prints to the console goes out on TX and cannot
# be read back, so `socat TCP-LISTEN:7000 ... FILE:/dev/ttyS0` delivers nothing
# (measured: 0 bytes, with and without the getty holding the port). Sharing the
# port with serial-getty fails too -- agetty holds it exclusively.
#
# The log does exist in the kernel ring buffer, which journald reads from
# /dev/kmsg. Streaming that over TCP gives the board's own console output to any
# client, with no USB-serial adapter, no laptop attached and no dependency on a
# working USB enumeration after a warm reboot.
#
#   client:  socat - TCP:100.64.0.18:7001      (or: nc 100.64.0.18 7001)
{
  systemd.services."kernel-log-tcp" = {
    description = "Serve the kernel log over TCP";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-journald.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:7001,reuseaddr,fork EXEC:'${pkgs.systemd}/bin/journalctl -f -k -o short-iso'";
      Restart = "always";
      RestartSec = "2s";
      Nice = 5;
    };
  };

  networking.firewall.allowedTCPPorts = [ 7001 ];
}
