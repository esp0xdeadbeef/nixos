{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    lastpass-cli
    tpm2-tss
    tpm2-tools
    openssl
  ];

}
