{
  config,
  pkgs,
  lib,
  ...
}:
{
#shamelessly joinked from https://github.com/mdlayher/homelab/blob/main/nixos/lib/system.nix
environment = {
    # Put ~/bin in PATH.
    # homeBinInPath = true;
    systemPackages = with pkgs; [

      # nix home manager
      home-manager
      # required for my (esp0xdeadbeef) lxc mounts
      bindfs

      # terminals
      xterm
      alacritty

      # encryption:
      # cli encrypt a message with key generator:
      age
      # sops:
      sops
      # pgp
      gnupg


      # fuzzy finder in terminal
      fzf

      # taskmanager in linux, holy shit this is cool!
      btop
      # check out byobu-tmux (f12=ctrl+b)
      byobu
      # bios / uefi tool
      dmidecode
      # monitoring of network traffic
      ethtool
      # update firmware
      fwupd
      # compiler
      gcc
      # github cli
      git
      # make utils
      gnumake
      # top but better:
      htop
      # internet top:
      iftop
      # com / harddisk monitoring
      iotop
      # benchmark a communication line speed
      iperf3
      # json parser
      jq
      # nuke it all:
      killall
      # sensor temps
      lm_sensors
      # hardware listing
      lshw
      # list of open files (everything is a file)
      lsof
      # scsi listing tool
      lsscsi
      # instead of screen we can use this to communicate serial:
      minicom
      # make passwords in tty
      mkpasswd
      #traceroute tool
      mtr
      # traceroute self
      traceroute
      # file editing
      neovim

      # ipv6 - Looks up an on-link IPv6 node link-layer address (Neighbor Discovery)
      ndisc6

      # flex tool:
      neofetch

      # rfc formatter:
      nixfmt-rfc-style

      # network port scan tool
      nmap

      # wireshark but then in the terminal
      tshark

      # it's always dns ;)
      dnsutils
      # some stats about the CPU
      nmon

      # pci utils? same as lspci?
      pciutils

      # no idea what this is:
      # pkg-config

      # pipe tooling:
      pv

      # rg for the win, faster grepping:
      ripgrep

      # harddisk tooling:
      # sudo smartctl --all /dev/nvme0n1
      smartmontools

      # stats about the current system
      sysstat

      # wireshark cli.
      tcpdump

      # multiple shells in one terminal session
      tmux
      # ez mode for find:
      tree
      # xxd hex dump:
      unixtools.xxd
      #unziping a archive zip file:
      unzip
      # usb listing services like lsusb
      usbutils
      # curl / wget (http and simular tooling):
      wget
      curl
    ];
  };
}