{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    xdotool
    arandr
    xclip
    kubectl
    docker
    kind
    podman-compose

    xkill

  ];
}
