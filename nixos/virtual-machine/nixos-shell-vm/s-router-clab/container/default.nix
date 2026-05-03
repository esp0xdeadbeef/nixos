{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./networking.nix
    ./dns.nix
  ];

  networking.firewall.enable = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "yes";
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
  ];

  environment.systemPackages = with pkgs; [
    bashInteractive
    containerlab
    curl
    docker
    git
    gnumake
    gnused
    gnutar
    htop
    iproute2
    iputils
    jq
    nftables
    python3
    ripgrep
    tcpdump
    traceroute
    vim
  ];

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  system.stateVersion = "25.11";
}
