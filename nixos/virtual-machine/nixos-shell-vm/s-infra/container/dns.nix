{ lib, ... }:
{
  #services.resolved.enable = false;
  services.resolved.enable = true;

  networking.nameservers = [
    "1.1.1.1"
    "8.8.8.8"
    "2606:4700:4700::1111"
    "2606:4700:4700::1001"
    "2606:4700:4700::1001"
    "2001:4860:4860::8888"
    "2001:4860:4860::8844"
  ];
  networking.useHostResolvConf = lib.mkForce false;
}
