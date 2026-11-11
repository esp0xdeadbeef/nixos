{ config, pkgs, ... }:
{
  environment.etc.hosts.enable = false;
  security.polkit.enable = true;
  # #services.openssh.enable = true;
  # #services.openssh.settings.X11Forwarding = true;

  # creating a a softlink for burp shit (suite)
  # environment.etc."burp/jython.jar" = {
  #   # If you have a jython package in your Nixpkgs, you can use it like:
  #   source = "${pkgs.jython}/jython.jar";
  #   # Alternatively, if you want to hardcode the current store path, you can:
  #   # source = "/nix/store/akb86svs9qd561a5l27252pqyd8dyds4-jython-2.7.4/jython.jar";
  # };

  # environment.etc."burp/jruby.jar" = {
  #   source = "${pkgs.jruby}/lib/jruby.jar";
  # };

  programs.wireshark.enable = true;
  # also check nix-index btw :)
  # services.locate = {
  #   enable = true;
  #   package = pkgs.plocate;
  #   #localuser = null;
  #   # prunePaths = options.services.locate.prunePaths.default ++ [ "/mnt/pool" ];
  # };

  # List packages installed in system profile. To search, run:
  # $ nix search wget

  environment.systemPackages = with pkgs; [
    nix-index
    navi
    nixfmt
    pulseaudio
    nmap
    azure-cli
    unzip
    samba4Full
    rlwrap
    lastpass-cli
    tpm2-tss
    gh
    sshpass

    man
    man-pages
    openssl
    tpm2-tools
    jq
    usbutils
    file
    jython
    gron
    mokutil
    man
    pciutils
    lshw
    # neofetch
    fzf
    git
    traceroute
    tmux
    dig
    bindfs
    wget
    python3
    libusb1
    kubectl
    docker
    kind
    python3.pkgs.evdev
    python3.pkgs.pygraphviz
    podman-compose
    tcpdump
    wireshark
    tshark
    # ventoy-full
    htop
  ];

}
