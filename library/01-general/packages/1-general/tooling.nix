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
      # terminals
      xterm
      alacritty

      # file command, what type of file do we have on our hands:
      file

      # encryption:
      # cli encrypt a message with key generator:
      age
      # sops:
      sops
      # pgp
      gnupg

      # hardware Secure Boot Manager
      sbctl

      # utility to manipulate machine owner keys
      mokutil

      # fuzzy finder in terminal
      fzf

      # always install man pages:
      man
      man-pages

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
      # neovim

      # ipv6 - Looks up an on-link IPv6 node link-layer address (Neighbor Discovery)
      ndisc6

      # flex tool
      # neofetch (depricated)
      fastfetch

      # rfc formatter:
      nixfmt

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
      tshark

      # multiple shells in one terminal session
      tmux
      # ez mode for find:
      tree
      # xxd hex dump:
      unixtools.xxd

      # usb listing services like lsusb
      usbutils
      libusb1

      # general purpose, and usb debugging:
      screen

      # curl / wget (http and simular tooling):
      wget
      curl

      # formatting tools like:
      # mkfs.ext4 /dev/sdX1
      e2fsprogs
    ];
  };
}
