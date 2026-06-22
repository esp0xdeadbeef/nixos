{ lib, pkgs, ... }:
{
  security.sudo.extraConfig = lib.mkAfter ''
    Defaults lecture = never
  '';

  environment.systemPackages = with pkgs; [
    age
    curl
    dig
    git
    jq
    lsof
    mtr
    procps
    ripgrep
    sops
    tcpdump
    tmux
    traceroute
    vim
    wget
  ];
}
