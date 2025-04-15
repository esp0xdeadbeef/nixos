{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    okular
    # firefox already installed
    
  ];
}
