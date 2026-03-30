{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  unstablePkgs = import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
  };
in
{
  environment.etc.hosts.enable = false;
  programs.firefox.enable = true;
  # programs.neovim.enable = true;
  # programs.neovim.defaultEditor = true;
  services.supergfxd.enable = true;
  security.polkit.enable = true;
  #services.openssh.enable = true;
  #services.openssh.settings.X11Forwarding = true;

  # creating a a softlink for burp shit (suite)
  environment.etc."burp/jython.jar" = {
    # If you have a jython package in your Nixpkgs, you can use it like:
    source = "${pkgs.jython}/jython.jar";
    # Alternatively, if you want to hardcode the current store path, you can:
    # source = "/nix/store/akb86svs9qd561a5l27252pqyd8dyds4-jython-2.7.4/jython.jar";
  };

  environment.etc."burp/jruby.jar" = {
    source = "${pkgs.jruby}/lib/jruby.jar";
  };

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

  environment.systemPackages =
    (with pkgs; [
      home-manager
      nix-index
      arandr
      #hyprland
      #rofi
      #autorandr
      fast-cli
      #cudaPackages.cudatoolkit
      alacritty
      #flameshot
      #google-chrome
      navi
      nixfmt-rfc-style
      pulseaudio
      feroxbuster
      nuclei
      gau # wayback machine
      nmap
      # inotify service (otherwise flameshot crashes)
      dunst
      unzip
      metasploit
      samba4Full
      rlwrap
      lastpass-cli

      tpm2-tss
      vim
      responder
      playerctl
      autorandr
      gh
      sshpass
      man-pages
      sbctl
      openssl
      tpm2-tools
      jq
      usbutils
      file
      jython
      gron
      mokutil
      man
      #dex
      pciutils
      autotiling
      lshw
      neofetch

      # virtualization:
      podman
      docker
      lxc

      # easier searching:
      fzf
      # package manager:
      git
      traceroute
      tmux
      dig
      #(burpsuite.override { proEdition = true; })
      bindfs
      xclip
      wget
      obsidian
      #qemu
      libvirt
      spotify
      virt-manager
      virt-viewer
      spice
      spice-gtk
      spice-protocol
      win-spice
      python3
      libusb1
      # firefox
      # thunderbird
      #discord
      #slack
      kubectl
      docker
      kind
      #teams
      brave
      python3.pkgs.evdev
      python3.pkgs.pygraphviz
      podman-compose
      #google-chrome
      #chromium
      #signal-desktop
      sbctl
      tcpdump
      wireshark
      tshark
      # ventoy-full
    ])
    ++ [
      unstablePkgs.zap
    ];
}
