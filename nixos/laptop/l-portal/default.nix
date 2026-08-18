{ inputs
, lib
, pkgs
, profiles
, relativeRepo
, ...
}:
let
  hostName = builtins.baseNameOf (builtins.dirOf __curPos.file);
  keyFor = host: lib.fileContents (relativeRepo.sourcePath "ssh-keys/deadbeef/${host}.pub");
in
{
  imports = [
    profiles.nixos.base.default
    profiles.nixos.laptop.default
    profiles.nixos.network.nebula-mesh
    profiles.nixos.boot.usb-removable
    profiles.nixos.desktop.i3
    profiles.nixos.editors.neovim
    profiles.nixos.hardware.clock-sync
    profiles.nixos.home-manager.deadbeef
    profiles.nixos.nix.flake-inputs
    profiles.nixos.nixpkgs.local-overlays
    profiles.nixos.sops.persist-root-age-key-file
    profiles.nixos.sops.persist-root-ssh
    profiles.nixos.ssh.password-login
    profiles.nixos.users.deadbeef-sops

    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops

    ./hardware/bootloader.nix
    ./hardware/hardware-configuration.nix
    ./hardware/impermanence.nix
    ./disko.nix
    ./packages/packages.nix
    ./packages/widevine.nix

    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x13s

    profiles.nixos.impermanence.module

    (relativeRepo.module "library/01-general/desktop/fonts.nix")

    #(relativeRepo.module "library/01-general/desktop/shell-env.nix")
  ];

  sops.defaultSopsFile = relativeRepo.sourcePath "secrets/${hostName}-default.yaml";
  sops.secrets."l-portal-mac" = {
    sopsFile = relativeRepo.sourcePath "secrets/l-portal-mac.yaml";
    key = "mac";
    path = "/run/secrets/l-portal-mac";
  };

  sops.secrets."cobalt-wifi" = {
    sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-wifi.yaml";
    key = "";
    path = "/run/secrets/cobalt-wifi";
  };

  systemd.services.cobalt-wifi-env = {
    description = "Extract cobalt-clients Wi-Fi credentials for NetworkManager";
    after = [ "sops-install-secrets.service" ];
    before = [ "NetworkManager-ensure-profiles.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      umask 077
      ${pkgs.yq-go}/bin/yq -r \
        '"COBALT_CLIENTS_SSID=" + .["cobalt-clients"].ssid, "COBALT_CLIENTS_PSK=" + .["cobalt-clients"].psk' \
        /run/secrets/cobalt-wifi > /run/cobalt-wifi.env
    '';
  };

  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ "/run/cobalt-wifi.env" ];
    profiles.cobalt-clients = {
      connection = {
        id = "cobalt-clients";
        type = "wifi";
        autoconnect = true;
        autoconnect-priority = 200;
      };
      wifi = {
        mode = "infrastructure";
        ssid = "$COBALT_CLIENTS_SSID";
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk = "$COBALT_CLIENTS_PSK";
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
  };

  time.timeZone = "Europe/Amsterdam";

  nixpkgs = {
    overlays = [
      # Widevine patch.
      inputs.nixos-aarch64-widevine.overlays.default
    ];

    hostPlatform = "aarch64-linux";
  };

  networking.hostName = hostName;
  networking.networkmanager.enable = true;
  services.udev.extraRules =
    let
      lPortalMacScript = pkgs.writeShellScript "l-portal-set-mac" ''
        exec ${pkgs.iproute2}/bin/ip link set dev "$1" address "$(cat /run/secrets/l-portal-mac)"
      '';
    in
    ''
      ACTION=="add", SUBSYSTEM=="net", KERNELS=="0006:01:00.0", RUN+="${lPortalMacScript} $name"
    '';

  # The NIC is probed before sops-install-secrets runs, so re-trigger the udev
  # rule once the SOPS MAC secret is available.
  systemd.services.l-portal-mac-udev = {
    description = "Apply the SOPS-backed l-portal NIC MAC after secrets are ready";
    wantedBy = [ "multi-user.target" ];
    after = [ "sops-install-secrets.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.systemd}/bin/udevadm trigger --subsystem-match=net --attr-match=KERNELS=0006:01:00.0
    '';
  };
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

  users.users.deadbeef = {
    openssh.authorizedKeys.keys = [
      (keyFor "l-portal")
      (keyFor "l-esp")
      (keyFor "l-esp-alt")
      (keyFor "l-esp-root")
    ];

    extraGroups = [
      "wheel"
    ];
  };

  system.stateVersion = "24.11";
}
