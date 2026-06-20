{ pkgs, ... }:
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };

  environment.systemPackages = with pkgs; [
    age
    curl
    dig
    git
    jq
    lsof
    mtr
    neovim
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
