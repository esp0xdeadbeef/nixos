{ pkgs, config, lib, ... }:
{
  containers."${config.networking.hostName}-container".extraVeths = lib.mkForce {
    veth0.hostBridge = "vlan2";
  };
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    gron
    jq
    ripgrep
  ];

}
