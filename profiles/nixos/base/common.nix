{ pkgs, ... }:
{
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
