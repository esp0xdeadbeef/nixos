### FILE: ./radvd.nix ###
{ pkgs, ... }:
{
  systemd.services.radvd = {
    description = "Router Advertisement Daemon (dynamic config in /run/radvd.conf)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "v6-pd-generate.service" ];
    wants = [ "v6-pd-generate.service" ];

    path = [ pkgs.radvd ];

    serviceConfig = {
      ExecStart = "${pkgs.radvd}/sbin/radvd -n -C /run/radvd.conf";
      Restart = "always";
      RestartSec = 2;
    };
  };
}

