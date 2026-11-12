{ inputs
, lib
, pkgs
, profiles
, relativeRepo
, ...
}:
let
  # l-portal-unstable -- the SAME physical ThinkPad X13s as l-portal, but built
  # against the unpinned nixos-hardware work from NixOS/nixos-hardware#1751
  # (the x13s options/patches rework) instead of the pinned esp0xdeadbeef fork.
  #
  # This host exists so the port can be built, compared and booted WITHOUT
  # touching l-portal, which stays the known-good rollback target. Nothing here
  # is deployed by default.
  #
  # Naming: the flake attribute (directory name) and the system hostname are
  # `l-portal-unstable`, but the *machine identity* used for secrets stays
  # `l-portal`: it is the same hardware, the same age/SSH keys and the same
  # SOPS files. Changing that would silently change which secrets decrypt.
  hostName = builtins.baseNameOf (builtins.dirOf __curPos.file);
  identityName = "l-portal";
  keyFor = host: lib.fileContents (relativeRepo.sourceModule "ssh-keys/deadbeef/${host}.pub");
  # Public keys of the dedicated remote-builder identities for the hosts allowed
  # to offload builds to this builder (see profiles.nixos.nix.remote-builder-client).
  remoteBuilderKeyFor = host: lib.fileContents (relativeRepo.sourceModule "ssh-keys/deadbeef/remote-builder/${host}.pub");
in
{
  imports = [
    profiles.nixos.base.default
    profiles.nixos.laptop.default
    profiles.nixos.network.cobalt-wifi-client
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
    profiles.nixos.users.sudo-nopasswd
    profiles.nixos.nix.remote-builder-client
    profiles.nixos.nix.remote-builder-server

    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops

    ./hardware/bootloader.nix
    ./hardware/hardware-configuration.nix
    ./hardware/impermanence.nix
    # NOTE: no ./hardware/tpm.nix here. The PR carries the same four TPM
    # patches (byte-identical) plus their config, selected via
    # `hardware.x13s.patches.tpm.enable` below. Importing both would apply the
    # series twice and fail the patch phase.
    ./disko.nix
    ./packages/packages.nix
    ./packages/widevine.nix

    # The nixos-hardware fork branch that stacks PR #1751's x13s rework on top
    # of the bpi-r4-pro support, pinned by rev in flake.nix.
    inputs.nixos-hardware-x13s.nixosModules.lenovo-thinkpad-x13s

    profiles.nixos.impermanence.module

    (relativeRepo.module "library/01-general/desktop/fonts.nix")

    #(relativeRepo.module "library/01-general/desktop/shell-env.nix")
  ];

  sops.defaultSopsFile = relativeRepo.sourcePath "secrets/${identityName}-default.yaml";
  sops.secrets."l-portal-mac" = {
    sopsFile = relativeRepo.sourcePath "secrets/l-portal-mac.yaml";
    key = "mac";
    path = "/run/secrets/l-portal-mac";
  };

  time.timeZone = "Europe/Amsterdam";

  nixpkgs = {
    overlays = [
      # Widevine patch.
      inputs.nixos-aarch64-widevine.overlays.default
    ];

    hostPlatform = "aarch64-linux";

    # This host is instantiated from `inputs.nixpkgs-unstable` (see
    # `nixpkgsFor` in flake.nix) while the flake's own `nixpkgs` input is the
    # pinned nixos-26.05. nixpkgs hard-codes `nix.registry.nixpkgs` to
    # `config.nixpkgs.pkgs.path` when `nixpkgs.flake.setFlakeRegistry` is on
    # (the default for flake-built systems), and *also* derives it from the
    # flake's nixpkgs -- two definitions that disagree here and abort eval with
    # "conflicting definition values" for `nix.registry.nixpkgs.to.path`.
    # This host is variant-only and never used as a `nixpkgs` registry source,
    # so the pin is not needed.
    flake.setFlakeRegistry = false;
    flake.setNixPath = false;
  };

  networking.hostName = hostName;

  # Same machine, same user, same keys: reuse l-portal's home configuration
  # rather than duplicating the whole home-manager tree.
  local.homeManager.hostName = identityName;

  # Cloned Wi-Fi MAC is a property of the *machine* (l-portal has the
  # `wifi-mac` SOPS secret), not of this variant's flake attribute name. The
  # module defaults this to `hostName == "l-portal"`, which the variant name
  # would otherwise miss.
  local.network.private.clonedMac.enable = true;

  # PR #1751 X13s options.
  hardware.lenovo.x13s = {
    # Empty string means "do not touch the MAC". The default (null) would have
    # the module generate a machine-id-derived MAC, competing with the
    # SOPS-backed rule below for the same KERNELS match. `""` keeps the
    # `services.udev.extraRules` in this file the sole owner of the address.
    wifiMAC = "";

    # Left at the default (null) on purpose: that is PR #1751's
    # machine-id-derived MAC path, and the whole point of this variant is to
    # exercise the module rather than overwrite it. The module's
    # `bluetooth-x13s-mac` service therefore owns the address; there is no
    # SOPS-backed BT rule here competing for hci0. See the Bluetooth block
    # below for why the enable flag is required at all.
    # bluetoothMAC = null;
  };

  # PR #1751 testing: the module's Bluetooth MAC block is gated on
  # `hardware.bluetooth.enable`, so with Bluetooth off none of it runs and the
  # `bluetooth-x13s-mac` oneshot (wait for hci0 firmware -> btmgmt pub
  # public-addr) is never exercised. Enabling it here is what actually tests
  # that code path on this hardware.
  hardware.bluetooth.enable = true;

  # The TPM the Clevis chain depends on: the Qualcomm QSEECOM transport is not
  # mainline, so these patches are required. They are the same four patches
  # l-portal carries locally (byte-identical), moved into the module so a
  # kernel baseline can be selected. See hardware/bootloader.nix for how the
  # TPM is used (Tang AND TPM2 `sss` chain for root).
  hardware.x13s.patches.tpm.enable = true;

  # PR #1751 testing: the camera only captures *once* per boot on mainline;
  # after one capture the CAMNOC AXI RCG is left pointing at camcc_pll0 and
  # the next titan_top_gdsc collapse never reaches PWR_ON. This patch set marks
  # the camnoc_axi/slow_ahb/fast_ahb RCGs shared so the domain powers up
  # cleanly across repeated captures -- which is exactly what the acceptance
  # test (read the same sheet of paper several times) exercises.
  hardware.x13s.patches.camera.enable = true;

  local.nix.remoteBuilderServer = {
    enable = true;
    # l-portal is the fleet's native aarch64 builder (ThinkPad X13s, Snapdragon
    # 8cx Gen 3). No binfmt: it serves aarch64 directly. It is the weakest host
    # (8 cores, 14 GiB, passively cooled), so it is capped to ~2 build cores.
    clients = {
      l-envil.key = remoteBuilderKeyFor "l-envil";
      l-esp.key = remoteBuilderKeyFor "l-esp";
      s-gamma.key = remoteBuilderKeyFor "s-gamma";
      s-sigma.key = remoteBuilderKeyFor "s-sigma";
      # s-nodus (BPI-R4 Pro 4E): 4-core aarch64 board with 4 GiB of RAM.  Its
      # large closures cannot be built on the board, so it offloads here -- and
      # l-portal is the native aarch64 builder, so this is the one s-nodus most
      # wants to reach.  Small config derivations still build locally
      # (nix.settings.max-jobs = 2) so the board can bootstrap when no builder
      # is reachable.
      s-nodus.key = remoteBuilderKeyFor "s-nodus";
      s-tau.key = remoteBuilderKeyFor "s-tau";
    };
  };

  local.nix.remoteBuilderClient = {
    self = "l-portal-builder";
    class = "laptop";
  };

  # Limit the daemon to ~2 build cores: at most 2 concurrent single-core jobs
  # for local and offloaded builds alike, leaving the rest of the SoC free for
  # the portal's own duties.
  nix.settings = {
    max-jobs = 2;
    cores = 1;
  };
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
