{ config, lib, pkgs, ... }:
{
  config = lib.mkIf config.services.xserver.enable {
    environment.systemPackages = with pkgs; [
      arandr
      xclip
      xdotool
      xkill
    ];
  };
}
