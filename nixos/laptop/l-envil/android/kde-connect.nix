{ config
, pkgs
, lib
, ...
}:

{
  environment.systemPackages = with pkgs; [
  ];
  programs.kdeconnect = {
    enable = true;
  };
}
