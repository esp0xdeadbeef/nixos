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
    profiles.nixos.workstation.pentest-cleanup
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
  systemd.services.xlayoutdisplay-hotplug = let
    applyLayout = pkgs.writeShellScript "xlayoutdisplay-apply" ''
      set -eu

      uid=""

      while read -r session _; do
        [ "$(${pkgs.systemd}/bin/loginctl show-session "$session" -p Type --value)" = "x11" ] || continue
        [ "$(${pkgs.systemd}/bin/loginctl show-session "$session" -p Active --value)" = "yes" ] || continue

        uid="$(${pkgs.systemd}/bin/loginctl show-session "$session" -p User --value)"
        break
      done < <(${pkgs.systemd}/bin/loginctl list-sessions --no-legend)

      if [ -z "$uid" ]; then
        echo "No active X11 session found; skipping display layout." >&2
        exit 0
      fi

      home="$(${pkgs.getent}/bin/getent passwd "$uid" | ${pkgs.coreutils}/bin/cut -d: -f6)"
      if [ -z "$home" ]; then
        echo "No home directory found for uid $uid; skipping display layout." >&2
        exit 0
      fi

      display=""
      for socket in /tmp/.X11-unix/X*; do
        [ -S "$socket" ] || continue
        [ "$(${pkgs.coreutils}/bin/stat -c %u "$socket")" = "$uid" ] || continue
        display=":''${socket##*/X}"
        break
      done

      if [ -z "$display" ]; then
        echo "No X11 socket found for uid $uid; skipping display layout." >&2
        exit 0
      fi

      xauthority=""
      for pid in $(${pkgs.procps}/bin/pgrep -x Xorg || true); do
        [ "$(${pkgs.coreutils}/bin/stat -c %u "/proc/$pid")" = "$uid" ] || continue

        xauthority="$(
          ${pkgs.coreutils}/bin/tr '\0' '\n' < "/proc/$pid/cmdline" \
            | ${pkgs.gawk}/bin/awk 'prev { print; exit } $0 == "-auth" { prev = 1 }'
        )"
        [ -n "$xauthority" ] && break
      done

      if [ -z "$xauthority" ]; then
        echo "No Xauthority path found for uid $uid; skipping display layout." >&2
        exit 0
      fi

      export HOME="$home"
      export DISPLAY="$display"
      export XAUTHORITY="$xauthority"
      export XDG_RUNTIME_DIR="/run/user/$uid"

      exec ${pkgs.xlayoutdisplay}/bin/xlayoutdisplay -w 2
    '';

    monitorLayout = pkgs.writeShellScript "xlayoutdisplay-hotplug-monitor" ''
      set -eu

      pending_apply=""

      schedule_apply() {
        if [ -n "$pending_apply" ] && ${pkgs.procps}/bin/kill -0 "$pending_apply" 2>/dev/null; then
          ${pkgs.procps}/bin/kill "$pending_apply" 2>/dev/null || true
          wait "$pending_apply" 2>/dev/null || true
        fi

        (
          ${pkgs.coreutils}/bin/sleep 4
          ${applyLayout} || true
        ) &
        pending_apply="$!"
      }

      trap 'if [ -n "$pending_apply" ]; then ${pkgs.procps}/bin/kill "$pending_apply" 2>/dev/null || true; fi' EXIT

      ${applyLayout} || true

      ${pkgs.systemd}/bin/udevadm monitor --kernel --udev --subsystem-match=drm --subsystem-match=usb \
        | while read -r line; do
            case "$line" in
              KERNEL* | UDEV*) schedule_apply ;;
            esac
          done
    '';
  in {
    description = "Apply xlayoutdisplay after display hotplug";
    wantedBy = [ "graphical.target" ];
    after = [ "display-manager.service" ];
    path = [
      pkgs.xrandr
      pkgs.xrdb
    ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${monitorLayout}";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
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
