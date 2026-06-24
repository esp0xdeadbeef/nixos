{ config
, pkgs
, lib
, ...
}:
{
  environment.etc.hosts.enable = false;
  programs.firefox.enable = true;
  # programs.neovim.enable = true;
  # programs.neovim.defaultEditor = true;
  services.supergfxd.enable = true;
  security.polkit.enable = true;
  #services.openssh.enable = true;
  #services.openssh.settings.X11Forwarding = true;

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
      #hyprland
      #rofi
      #autorandr
      #cudaPackages.cudatoolkit
      alacritty
      #flameshot
      #google-chrome
      navi
      nixfmt
      pulseaudio
      nmap
      unzip
      samba4Full
      rlwrap
      lastpass-cli

      tpm2-tss
      vim
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
      lshw

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
      bindfs
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
    ]);
}
