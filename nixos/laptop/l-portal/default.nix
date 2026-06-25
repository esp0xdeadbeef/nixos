{ inputs
, outputs
, lib
, config
, pkgs
, profiles
, outPath
, ...
}:
let
  hostName = builtins.baseNameOf (builtins.dirOf __curPos.file);
  keyFor = host: lib.fileContents "${outPath}/ssh-keys/deadbeef/${host}.pub";
in
{
  imports = [
    profiles.nixos.base.default
    profiles.nixos.laptop.default
    profiles.nixos.boot.usb-removable
    profiles.nixos.hardware.clock-sync

    inputs.disko.nixosModules.disko

    ./hardware/bootloader.nix
    ./hardware/hardware-configuration.nix
    ./hardware/impermanence.nix
    ./disko.nix
    ./packages/packages.nix
    ./packages/widevine.nix

    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x13s

    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager

    # inputs.nixos-x13s.nixosModules.default
    "${outPath}/library/02-window-manager-i3/default.nix"

    "${outPath}/library/01-general/system/garbage-collection.nix"
    "${outPath}/library/01-general/system/autoupdate.nix"
    "${outPath}/library/01-general/desktop/fonts.nix"

    #"${outPath}/library/01-general/desktop/shell-env.nix"

    inputs.sops-nix.nixosModules.sops
  ];
  sops.defaultSopsFile = "${outPath}/secrets/${hostName}-default.yaml";
  sops.age.sshKeyPaths = [ "/persist/root/.ssh/id_ed25519" ];
  sops.age.keyFile = "/persist/root/.config/sops/age/keys.txt";
  sops.secrets."deadbeef-passwd" = {
    neededForUsers = true; # make it available before the user is created
  };
  time.timeZone = "Europe/Amsterdam";

  home-manager = {
    sharedModules = [
      inputs.sops-nix.homeManagerModules.sops
    ];
    extraSpecialArgs = {
      inherit inputs outputs profiles outPath;
    };

    users = {
      deadbeef = import "${outPath}/home-manager/${hostName}/home.nix";
    };
  };

  nixpkgs = {
    overlays = [
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages

      # Widevine patch.
      inputs.nixos-aarch64-widevine.overlays.default
    ];

    config = {
      allowUnfree = true;
    };

    hostPlatform = "aarch64-linux";
  };

  nix =
    let
      flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
    in
    {
      settings = {
        experimental-features = "nix-command flakes";

        # Opinionated: disable global registry.
        flake-registry = "";

        # Workaround for:
        # https://github.com/NixOS/nix/issues/9574
        nix-path = config.nix.nixPath;
      };

      # Opinionated: disable channels.
      channel.enable = false;

      # Opinionated: make flake registry and nix path match flake inputs.
      registry = lib.mapAttrs (_: flake: { inherit flake; }) flakeInputs;
      nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
    };

  networking.hostName = hostName;
  networking.networkmanager.enable = true;
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", KERNELS=="0006:01:00.0", RUN+="${pkgs.iproute2}/bin/ip link set dev $name address 00:03:7f:12:68:72"
  '';
  warnings = [
    "l-portal: systemctl hibernate is intentionally blocked because X13s cold hibernate restore currently crashes after image restore; use documented debug sysfs tests only."
  ];
  services.autorandr.enable = lib.mkForce false;
  systemd.services.systemd-hibernate = {
    serviceConfig.ExecStart = lib.mkForce [
      ""
      (pkgs.writeShellScript "l-portal-block-hibernate" ''
        printf '%s\n' \
          "ERROR: hibernate is disabled on l-portal." \
          "Reason: X13s cold hibernate restore currently crashes after the image is restored." \
          "See: nixos/laptop/l-portal/hibernate-analyse.md" >&2
        exit 1
      '')
    ];
  };
  # 4k blackscreens l-portal's external outputs because the framebuffer is too small.
  local.laptop.monitorLayouts.samsungLu28r55Desk = {
    enable = true;
    externalMaxResolution = "2560x1440";
  };
  security.rtkit.enable = true;
  hardware.enableRedistributableFirmware = true;

  specialisation = {
    debug.configuration = {
      system.autoUpgrade.enable = lib.mkForce false;
      boot.kernelParams = lib.mkBefore [
        "no_console_suspend"
        "ignore_loglevel"
        "printk.time=1"
        "log_buf_len=16M"
        "initcall_debug"
        "pm_debug_messages"
        "drm.debug=0x1e"
      ];
      # The X13s currently reports a storm of false pmic_resin power-key events
      # immediately after hibernate resume. If logind handles those, it powers
      # off the machine before we can diagnose the resumed session.
      services.logind.settings.Login = {
        HandlePowerKey = "ignore";
        HandlePowerKeyLongPress = "ignore";
      };
      # Debug-only hibernate isolation blacklists. Keep the base mhi module
      # available for ath11k_pci; only disable WWAN-facing drivers here.
      boot.blacklistedKernelModules = [
        "mhi_pci_generic"
        "mhi_wwan_ctrl"
        "mhi_wwan_mbim"
        "qcom_camss"
        "qcom_spmi_adc_tm5"
        "qcom_spmi_temp_alarm"
        "qcom_spmi_adc5"
      ];
      boot.kernel.sysctl = {
        "kernel.softlockup_panic" = 1;
        "kernel.panic" = 10;
      };
      systemd.services.systemd-hibernate.environment.SYSTEMD_SLEEP_FREEZE_USER_SESSIONS = "false";
    };
    manual-unlock.configuration = {
      local.boot.clevisTangUnlock.enable = lib.mkForce false;
    };
  };

  users.mutableUsers = false;

  users.users = {
    deadbeef = {
      #initialPassword = " ";
      hashedPasswordFile = config.sops.secrets.deadbeef-passwd.path;
      isNormalUser = true;

      openssh.authorizedKeys.keys = [
        (keyFor "l-portal")
        (keyFor "l-esp")
        (keyFor "l-esp-alt")
        (keyFor "l-esp-root")
        (keyFor "l-esp-rsa")
      ];

      extraGroups = [
        "wheel"
      ];
    };
  };

  services.openssh = {
    enable = true;

    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  system.stateVersion = "24.11";
}
