{ config, pkgs, ... }:
{
  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    dockerCompat = true;
  };
  environment.systemPackages = with pkgs; [
    containerlab
  ];

}
