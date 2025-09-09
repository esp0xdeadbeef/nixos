{
  config,
  pkgs,
  lib,
  ...
}:

let
  wl = pkgs.wordlists.override { lists = [ pkgs.seclists ]; };
in
{
  environment.systemPackages = [ wl ];

  systemd.tmpfiles.rules = [
    "L /usr/share/seclists - - - - ${wl}/share/wordlists/seclists"
  ];

}
