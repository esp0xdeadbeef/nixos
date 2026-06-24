{ config
, lib
, pkgs
, ...
}:
let
  ntpServers = lib.concatStringsSep " " config.networking.timeServers;
in
{
  systemd.services.sync-time-to-hwclock = {
    description = "Synchronize system time to the hardware clock";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "45s";
    };

    script = ''
      ${pkgs.coreutils}/bin/timeout 30s ${pkgs.ntp}/bin/ntpdate -u -b ${ntpServers}
      ${pkgs.coreutils}/bin/touch /var/lib/systemd/timesync/clock
      ${pkgs.util-linux}/bin/hwclock --systohc --utc
    '';
  };
}
