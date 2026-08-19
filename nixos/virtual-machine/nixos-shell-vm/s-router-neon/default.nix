{ inputs
, lib
, config
, pkgs
, relativeRepo
, outputs
, ...
}:
let
  hostName = "s-router-neon";
  modelSource = relativeRepo.sourcePath "prod-network/testing";
  deviceDir = relativeRepo.sourcePath "prod-network/testing/secrets/devices";
  deviceIds =
    map
      (name: lib.removeSuffix ".sops.yaml" name)
      (builtins.filter
        (name: lib.hasSuffix ".sops.yaml" name)
        (builtins.attrNames (builtins.readDir deviceDir)));
  qemuNetworkingOptions = [
    "-nic none"
    "-nic bridge,br=vmbr4,mac=52:54:00:12:34:56,model=virtio-net-pci"
    "-nic bridge,br=vmbr1,mac=52:54:00:12:34:57,model=virtio-net-pci"
  ];
in
{
  _module.args.sRouterProdProfile = {
    inherit modelSource;
    labSelector = null;
    productionSelector = "s-router-prod";
  };

  networking.hostName = lib.mkForce hostName;

  local.users.deadbeefSops.enable = false;

  users.users.deadbeef = {
    isNormalUser = true;
    hashedPassword = "!";
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;

  imports = [
    outputs.nixosModules.containerNetworkDefaults

    (relativeRepo.module "library/10-vms/nixos-shell-vm/host-config-routers-without-network")
    "${modelSource}/runtime-secrets.nix"

    (import ../s-router-prod/renderers.nix {
      inherit
        inputs
        lib
        modelSource
        ;

      hostName = "s-router-prod";
      controlPlaneModelInput = inputs.network-control-plane-model;
      networkRealizationModelInput = inputs.network-realization-model;
      nixosRendererInput = inputs.network-renderer-nixos;
      inventoryFileName = "inventory-all.nix";
      system = "x86_64-linux";
      selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-neon/default.nix";
    })
  ];

  system.stateVersion = lib.mkForce "26.05";

  # Per-device protected DHCP reservations (MACs). Encrypted to l-esp and
  # s-router-neon; bound into the access containers so kea can serve the
  # static vlan2 leases without the legacy full-lease JSON exports.
  sops.secrets = lib.listToAttrs (
    map
      (id: {
        name = "neon-device-${id}";
        value = {
          sopsFile = "${deviceDir}/${id}.sops.yaml";
          key = "mac";
          format = "yaml";
          path = "/run/secrets/devices/${id}";
        };
      })
      deviceIds
  );

  containers.access-vlan2.bindMounts = lib.listToAttrs (
    map
      (id: {
        name = "/run/secrets/devices/${id}";
        value = {
          hostPath = config.sops.secrets."neon-device-${id}".path;
          isReadOnly = true;
        };
      })
      deviceIds
  );

  virtualisation.qemu.networkingOptions = lib.mkForce qemuNetworkingOptions;

  # The neon renderer compiles the shared intent + combined inventory, and the
  # pinned renderer leaks cobalt's onyx overlay termination into this host.
  # Neon's own intent declares no onyx overlay; keep the stray container from
  # auto-starting (and demanding AirVPN secrets) until the renderer stops
  # leaking cross-site overlays.
  containers.core-vpn-onyx.autoStart = lib.mkForce false;
}
