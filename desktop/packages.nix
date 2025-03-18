{ config, pkgs, ... }: {
              programs.firefox.enable = true;
              programs.neovim.enable = true;
              programs.neovim.defaultEditor = true;
              nixpkgs.config.allowUnfree = true;
              services.supergfxd.enable = true;
              security.polkit.enable = true;
              #services.openssh.enable = true;
              #services.openssh.settings.X11Forwarding = true;

              programs.wireshark.enable = true;
services.locate = {
             enable = true;
    package = pkgs.plocate;
    #localuser = null;
    # prunePaths = options.services.locate.prunePaths.default ++ [ "/mnt/pool" ];
  };

              # List packages installed in system profile. To search, run:
              # $ nix search wget

              environment.systemPackages = with pkgs; [
home-manager
arandr
#                hyprland
#rofi
                #autorandr
		fast-cli
#                cudaPackages.cudatoolkit
                alacritty
#flameshot
#google-chrome
navi
                tpm2-tss
                vim
                responder
                nmap
		autorandr
sbctl
openssl
tpm2-tools
jq
usbutils
file
gron
mokutil
man
                glxinfo
                #dex
                pciutils
                autotiling
                lshw
                neofetch
                hashcat

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
                win-virtio
                win-spice
                python3
                libusb1
firefox
      thunderbird
        #discord
        #slack
        kubectl
        docker
        kind
        #teams
        brave
        #google-chrome
        #chromium
        #signal-desktop
sbctl
tcpdump
wireshark
tshark

              ];

}
