{ inputs
, outputs
, lib
, config
, pkgs
, profiles
, outPath
, ...
}:
{
  imports = [
    inputs.lanzaboote.nixosModules.lanzaboote
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p16s-intel-gen2
    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops

    profiles.nixos.workstation.full
    profiles.nixos.desktop.i3
    profiles.nixos.boot.usb-removable
    profiles.nixos.laptop.default
    profiles.nixos.workstation.android
    profiles.nixos.workstation.pentesting
    profiles.nixos.vm-host.nixos-shell

    ./connect-nas
    ./hardware
    ./llms
    #./osee
    ./signal
    ./torrents
    ./nebula-node
    ./optional
    ./nixos-shell-servers
  ];

  hardware.nvidia.prime = {
    intelBusId = "PCI:00:02:0";
    nvidiaBusId = "PCI:01:00:0";
  };

  # programs.nixvim = {
  #   enable = true;
  #   extraConfigLua = ''
  #     local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
  #     if not vim.loop.fs_stat(lazypath) then
  #       vim.fn.system({ "git", "clone", "--filter=blob:none",
  #         "https://github.com/folke/lazy.nvim.git", lazypath })
  #     end
  #     vim.opt.rtp:prepend(lazypath)
  #     require("lazy").setup({
  #       { "nvim-lua/plenary.nvim" },
  #       { "folke/snacks.nvim" },
  #       { "MunifTanjim/nui.nvim" },
  #       { "r-pletnev/pdfreader.nvim", dependencies = { "folke/snacks.nvim" } },
  #       { "yetone/avante.nvim", dependencies = { "MunifTanjim/nui.nvim", "nvim-lua/plenary.nvim" } },
  #       { "HakonHarnes/img-clip.nvim" },
  #     })
  #   '';
  #   extraPackages = with pkgs; [ git curl ];
  # };

  sops.defaultSopsFile = "${outPath}/secrets/l-esp-default.yaml";
  sops.age.sshKeyPaths = [ "/persist/root/.ssh/id_ed25519" ];
  sops.age.keyFile = "/persist/root/.config/sops/age/keys.txt";

  home-manager = {
    sharedModules = [
      inputs.sops-nix.homeManagerModules.sops
    ];
    extraSpecialArgs = {
      inherit
        inputs
        outPath
        outputs
        profiles
        ;
      primaryUserHome = config.local.users.primary.homeDirectory;
      primaryUser = config.local.users.primary.resolvedName;
    };
    users = {
      ${config.local.users.primary.resolvedName} = import "${outPath}/home-manager/l-esp/home.nix";
    };
  };

  nixpkgs = {
    overlays = [
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages
    ];
    config = {
      allowUnfree = true;
    };
  };

  nix =
    let
      flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
    in
    {
      settings = {
        # Enable flakes and new 'nix' command
        experimental-features = "nix-command flakes";
        # Opinionated: disable global registry
        flake-registry = "";
        # Workaround for https://github.com/NixOS/nix/issues/9574
        nix-path = config.nix.nixPath;
      };
      # Opinionated: disable channels
      channel.enable = false;

      # Opinionated: make flake registry and nix path match flake inputs
      registry = lib.mapAttrs (_: flake: { inherit flake; }) flakeInputs;
      nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
    };

  networking.hostName = "l-esp";
  networking.networkmanager.enable = true;
  services.autorandr.enable = lib.mkForce false;
  local.laptop.autorandrDefault.enable = false;
  local.laptop.xlayoutdisplayHotplug.configLines = [
    "wait=2"
    "rate=60"
    "primary=eDP-1"
    "order=DP-1-0.1.6"
    "order=HDMI-1-0"
    "order=eDP-1"
  ];
  local.workstation.android.enable = true;
  environment.etc.hosts.enable = false;
  local.users.primary.name = "deadbeef";
  security.pam.services.login.enableGnomeKeyring = true;
  systemd.tmpfiles.rules = [
    "d /home/deadbeef/.quickget/windows-10 0755 deadbeef users -"
    "h /home/deadbeef/.quickget/windows-10 - - - - +C"
    "d /home/deadbeef/.quickget/windows-11 0755 deadbeef users -"
    "h /home/deadbeef/.quickget/windows-11 - - - - +C"
  ];

  sops.secrets."${config.local.users.primary.resolvedName}-passwd" = {
    neededForUsers = true;
  };

  users.users.deadbeef = {
    hashedPasswordFile = config.sops.secrets."deadbeef-passwd".path;
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILNntUmNyQ+OYSEGHlXSBOQSWsJkXnx8E+zhfhGFRDuy deadbeef@l-portal"
    ];
  };

  environment = {
    systemPackages = [
      (pkgs.writeShellScriptBin "qemu-system-x86_64-uefi" ''
        qemu-system-x86_64 \
          -bios ${pkgs.OVMF.fd}/FV/OVMF.fd \
          "$@"
      '')
    ];
  };
  system.stateVersion = "24.11";
}
