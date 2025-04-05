{ config, pkgs, ... }:
{
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  services.openssh.enable = true;
  environment.systemPackages = with pkgs; [
    vim
    fzf
    networkmanager
    konsole
  ];
}
