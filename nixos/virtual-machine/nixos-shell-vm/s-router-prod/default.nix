{ inputs
, lib
, config
, pkgs
, relativeRepo
, outputs
, ...
}:
let
  hostName = "s-router-prod";
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

    (import ./renderers.nix {
      inherit
        inputs
        lib
        modelSource
        ;

      hostName = "s-router-prod";
      # s-router-prod is the pinned production render of the neon site:
      # it consumes the -prod network-* inputs in flake.lock for stability,
      # while s-router-neon tracks the same model against main for testing.
      controlPlaneModelInput = inputs.network-control-plane-model-prod;
      networkRealizationModelInput = inputs.network-realization-model-prod;
      nixosRendererInput = inputs.network-renderer-nixos-prod;
      intentFileName = "intent-neon.nix";
      inventoryFileName = "inventory-neon.nix";
      system = "x86_64-linux";
      selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-prod/default.nix";
    })
  ];

  system.stateVersion = lib.mkForce "26.05";

  # Per-device protected DHCP reservations (MACs). Encrypted to l-esp,
  # s-router-cobalt, s-router-prod, and s-router-neon; bound into the access
  # containers so kea can serve the static vlan2 leases without the legacy
  # full-lease JSON exports.
  sops.secrets = lib.listToAttrs (
    map
      (id: {
        name = "prod-device-${id}";
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
          hostPath = config.sops.secrets."prod-device-${id}".path;
          isReadOnly = true;
        };
      })
      deviceIds
  );

  containers.access-vlan3.bindMounts = lib.listToAttrs (
    map
      (id: {
        name = "/run/secrets/devices/${id}";
        value = {
          hostPath = config.sops.secrets."prod-device-${id}".path;
          isReadOnly = true;
        };
      })
      deviceIds
  );

  virtualisation.qemu.networkingOptions = lib.mkForce qemuNetworkingOptions;
}
