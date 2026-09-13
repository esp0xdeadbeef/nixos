{ inputs
, lib
, profiles
, relativeRepo
, ...
}:
let
  # Public keys of the dedicated remote-builder identities for the hosts allowed
  # to offload builds to this builder. Each client generates this once with
  # `sudo ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_remote-builder` and
  # commits the resulting .pub here (see profiles.nixos.nix.remote-builder-client).
  remoteBuilderKeyFor = host: lib.fileContents (relativeRepo.sourcePath "ssh-keys/deadbeef/remote-builder/${host}.pub");
in
{
  imports = [
    profiles.nixos.laptop.intel-workstation
    profiles.nixos.network.cobalt-wifi-client
    profiles.nixos.network.nebula-mesh
    profiles.nixos.vm-host.nixos-shell
    profiles.nixos.llm.ollama-base
    profiles.nixos.llm-clients.agents-all
    profiles.nixos.nix.remote-builder-client
    profiles.nixos.nix.remote-builder-server

    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p16s-intel-gen2

    ./connect-nas
    ./hardware
    ./optional
    ./nixos-shell-servers
  ];

  services.ollama.loadModels = profiles.nixos.llm.model-sets.workstation;

  local.nix.remoteBuilderServer = {
    enable = true;
    # l-esp is an x86_64 laptop; aarch64 offloads stay on l-portal (native) and
    # the emulating s-sigma/s-tau builders.
    clients = {
      l-envil.key = remoteBuilderKeyFor "l-envil";
      l-portal.key = remoteBuilderKeyFor "l-portal";
      s-gamma.key = remoteBuilderKeyFor "s-gamma";
      s-sigma.key = remoteBuilderKeyFor "s-sigma";
      s-tau.key = remoteBuilderKeyFor "s-tau";
    };
  };

  local.nix.remoteBuilderClient.excludeBuilders = [ "l-esp-builder" ];

  # i7-12850HX: 16 cores / 24 threads, also used interactively. Cap the daemon
  # so local and offloaded builds cannot fully throttle the laptop.
  nix.settings = {
    max-jobs = 4;
    cores = 4;
  };

  sops.secrets."deepseek-api".sopsFile = relativeRepo.sourcePath "secrets/l-esp-default-deadbeef.yaml";

  # l-esp-default.yaml is root-only; the cobalt lighthouse public IP is
  # kept in the deadbeef-scoped file instead.
  sops.secrets."nebula-cobalt-lighthouse-public-ip".sopsFile = relativeRepo.sourcePath "secrets/l-esp-default-deadbeef.yaml";

  hardware.nvidia.prime = {
    intelBusId = "PCI:00:02:0";
    nvidiaBusId = "PCI:01:00:0";
  };

  services.autorandr.enable = lib.mkForce false;
  local.laptop.autorandrDefault.enable = false;

  local.laptop.monitorLayouts.samsungLu28r55Desk = {
    enable = true;
    left = "samsung:lu28r55:f23519db73329d63";
    right = "samsung:lu28r55:f238aadb7335c99d";
    targetResolution = "3840x2160";
    internalScale = "1x1";
  };

  environment.etc.hosts.enable = false;

  # Workaround: nixpkgs man-db manualPages default errors.
  documentation.man.man-db.enable = false;

  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="0e8d", MODE="0660", GROUP="users", TAG+="uaccess"
    SUBSYSTEM=="usb", ATTR{idVendor}=="22d9", ATTR{idProduct}=="0006", MODE="0660", GROUP="users", TAG+="uaccess"
    SUBSYSTEM=="tty", KERNEL=="ttyACM[0-9]*", ATTRS{idVendor}=="22d9", ATTRS{idProduct}=="0006", MODE="0660", GROUP="users", TAG+="uaccess"
  '';

  systemd.tmpfiles.rules = [
    "d /home/deadbeef/.quickget/windows-10 0755 deadbeef users -"
    "h /home/deadbeef/.quickget/windows-10 - - - - +C"
    "d /home/deadbeef/.quickget/windows-11 0755 deadbeef users -"
    "h /home/deadbeef/.quickget/windows-11 - - - - +C"
  ];

  system.stateVersion = "24.11";
}
