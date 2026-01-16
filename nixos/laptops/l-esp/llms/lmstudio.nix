{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    lmstudio
  ];
}
