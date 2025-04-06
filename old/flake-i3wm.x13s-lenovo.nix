{
  inputs = {
    #nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixos-x13s.url = "github:BrainWart/x13s-nixos";
  };

  #outputs =
  #  { ... }@inputs:
  #  {
  outputs = { nixpkgs, nixos-x13s, ... }@inputs: {
      nixosConfigurations.example = inputs.nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          inputs.nixos-x13s.nixosModules.default
          ({ config, pkgs, ... }: {
            nixos-x13s.enable = true;
            #nixos-x13s.kernel = "jhovold"; # jhovold is default, but mainline supported
            nixos-x13s.bluetoothMac = "E9:1C:3B:F0:FD:8C";  # Example MAC address
            nixos-x13s.wifiMac = "8c:fd:f0:1c:3b:0a";

            # install multiple kernels! note this increases eval time for each specialization
            specialisation = {
              # note that activation of each specialization is required to copy the dtb to the EFI, and thus boot
              mainline.configuration.nixos-x13s.kernel = "mainline";
            };

            # allow unfree firmware
            nixpkgs.config.allowUnfree = true;
            services.openssh.enable = true;

            # define your fileSystems
            fileSystems."/".device = "/dev/nvme0n1p2";
fileSystems."/boot" = {
  device = "/dev/nvme0n1p1"; # Replace with your actual EFI partition device
  fsType = "vfat";
  options = [ "rw" "relatime" "umask=0077" ];
};

            system.stateVersion = "24.11";
#boot.initrd.availableKernelModules = [ "nvme" ]; # Optional but good
environment.systemPackages = with pkgs; [
  pkgs.util-linux
  pkgs.vim
  pkgs.fzf
  pkgs.lxc
  pkgs.wireshark
  pkgs.neofetch
];
virtualisation.lxc = {
    enable = true;
    unprivilegedContainers = true;

    defaultConfig = ''
        lxc.net.0.type = veth
        lxc.net.0.link = lxcbr0
        lxc.net.0.flags = up
        ##lxc.net.0.hwaddr = 00:16:3e:11:22:33
        lxc.apparmor.profile = generated
        lxc.apparmor.allow_nesting = 1
        lxc.idmap = u 0 100000 65535
        lxc.idmap = g 0 100000 65535
      '';
      usernetConfig = ''
        deadbeef veth lxcbr0 10
      '';
      lxcfs.enable = true;
  };
#  users.groups.lxc-user = { };
#users.groups.lxc-user = [ "deadbeef" ];
users.groups.lxc-user = { members = [ "deadbeef" ]; };
system.activationScripts.setLxcHomeACL = {
  text = ''
    export PATH=${pkgs.acl}/bin:$PATH
    # Grant container root (mapped to uid 100000) x access on /home/deadbeef
    mkdir -p /home/deadbeef/.config/lxc/
    cp /etc/lxc/default.conf /home/deadbeef/.config/lxc/default.conf
    chown deadbeef:users /home/deadbeef/.config
    chown deadbeef:users /home/deadbeef/.config/lxc
    chown deadbeef:users /home/deadbeef/.config/lxc/default.conf


    setfacl -m u:100000:--x /home/deadbeef
    setfacl -m u:100000:--x /home/deadbeef/.local
    setfacl -m u:100000:--x /home/deadbeef/.local/share/
    setfacl -m u:100000:--x /home/deadbeef/.local/share/lxc

  '';
};


boot.loader.efi.canTouchEfiVariables = true;
boot.loader.efi.efiSysMountPoint = "/boot";
boot.loader.systemd-boot.enable = true;



  services = {
    xserver = {
      layout = "us";
      xkbVariant = "";
      enable = true;
      windowManager.i3 = {
        enable = true;
        extraPackages = with pkgs; [
          i3status
        ];
      };
      desktopManager = {
        xterm.enable = false;
        xfce = {
          enable = true;
          noDesktop = true;
          enableXfwm = false;
        };
      };
      displayManager = {
        lightdm.enable = true;
        defaultSession = "xfce+i3";
      };
    };
    gvfs.enable = true;
    gnome.gnome-keyring.enable = true;
    blueman.enable = true;
    pipewire = {
      enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
    };
  };

  nixpkgs = {
    config = {
      pulseaudio = true;
    };
  };


  #############################
  # User and Groups
  #############################
  users.users.deadbeef = {
    isNormalUser = true;
    linger = true; # not sure what this does...
    description = "deadbeef";
    extraGroups = [
      "networkmanager"
      "wheel"
      "libvirtd"
      "video"
      "wireshark"
      "lxc-user"
    ];
    subGidRanges = [
      {
        startGid = 100000;
        count = 65536;
      }
    ];
    subUidRanges = [
      {
        startUid = 100000;
        count = 65536;
      }
    ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCa7PQ3hMgU3edhPZSY1eCTR0pwjfpO/Ywa5PXK8ieL2zlWTkD6C8UR+M0YsTlXw4XNy79Zl5JtDHqA043FCWcjikGV5mDRaZ/rS9Ew7+eEpXa+PwE18ckuQX9Pwq37kbJJAEf9A5ZtoEiDs/sa1+U0LzEF6iHqUwmHDV1PLXW84X0g+DJUqLDyF9FzkfdrwsRr1pkbwow83rHMIbIUGcCGgQCtfnPnlAdE8LbzxJRi7BSGJmIuG1xzGsYqJ4h3gCLiqmx7sIgGaOT66IxSi1xtEWBIxxRzkn85gnTIj8w1ydvT0AZPllguadvmkUiUif4QYE9CR7ik2mduh+d1CHln6Q2DZMnQOk6iM5TwHyYaPltuKx5w2jnXML9IIGlfYf8Kf/a+uD2uua+2PWBTtObrYoa6KX/nDY246qg3+eQ7o9HJD1s33WhLqYE7tpKuvU1cPXclOP0/C1UIUaj80o9niZmoNFRQHhp0IoNNs9LLL/mRE1/0QK3S2E5+wE7wSTc= deadbeef@l-esp"
    ];
    packages = with pkgs; [ ];
  };



          })
        ];
      };
    };
}