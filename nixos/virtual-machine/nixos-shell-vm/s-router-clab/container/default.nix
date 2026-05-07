{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./networking.nix
    ./dns.nix
    ./deploy.nix
  ];

  networking.firewall.enable = false;
  environment.etc.hosts.enable = false;

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

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.variables = {
    CLAB_RENDERER_REPO = "/run/s-router-clab/inputs/network-renderer-containerlab-linux-backend";
    CLAB_NETWORK_LABS = "/run/s-router-clab/inputs/network-labs";
    CLAB_CONTROL_PLANE_MODEL = "/run/s-router-clab/inputs/network-control-plane-model";
    CLAB_FRR_TOOLING_CACHE_DIR = "/persist/docker-image-cache/network-renderer-containerlab-linux-backend";
  };

  system.stateVersion = "25.11";
}
