{ config, pkgs, lib, ... }:

let
  wl = pkgs.wordlists.override { lists = [ pkgs.seclists ]; };
in {
  environment.systemPackages = [ wl ];
  environment.etc."seclists".source =
    "${wl}/share/wordlists/seclists"; # /etc/seclists -> Nix store
  environment.pathsToLink = [ "/share/wordlists/seclists" ]; # optional
}
