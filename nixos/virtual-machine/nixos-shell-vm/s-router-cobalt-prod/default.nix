{ inputs
, lib
, config
, relativeRepo
, ...
}:
let
  hostName = "s-router-cobalt-prod";
  system = "x86_64-linux";
  modelSource = relativeRepo.sourcePath "prod-network/current";
  deviceDir = relativeRepo.sourcePath "prod-network/current/secrets/devices";
  deviceIds =
    map
      (name: lib.removeSuffix ".age" name)
      (builtins.filter
        (name: lib.hasSuffix ".age" name)
        (builtins.attrNames (builtins.readDir deviceDir)));
  qemuNetworkingOptions = [
    "-nic none"
    "-nic bridge,br=br-cobalt-lan,model=virtio-net-pci"
    "-nic bridge,br=br-cobalt-wan,model=virtio-net-pci"
  ];
in
{
  _module.args.sRouterProdProfile = {
    inherit modelSource;
    labSelector = null;
    productionSelector = hostName;
  };

  networking.hostName = lib.mkForce hostName;

  imports = [
    (relativeRepo.module "library/10-vms/nixos-shell-vm/host-config-routers-without-network")

    (import ../s-router-prod/renderers.nix {
      inherit
        inputs
        lib
        modelSource
        ;

      hostName = "s-router-cobalt-prod";
      # Cobalt tracks the latest network-* main branches; s-router-prod stays
      # pinned to the -prod inputs in flake.lock for stability.
      controlPlaneModelInput = inputs.network-control-plane-model;
      networkRealizationModelInput = inputs.network-realization-model;
      nixosRendererInput = inputs.network-renderer-nixos;
      inherit system;
      selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-cobalt-prod/default.nix";
    })
  ];

  system.stateVersion = lib.mkForce "26.05";

  sops.secrets = lib.listToAttrs (
    map
      (id: {
        name = "cobalt-device-${id}";
        value = {
          sopsFile = "${deviceDir}/${id}.age";
          format = "binary";
          path = "/run/secrets/devices/${id}";
        };
      })
      deviceIds
  );

  containers.access-vlan2.bindMounts = lib.mkMerge [
    (lib.listToAttrs (
      map
        (id: {
          name = "/run/secrets/devices/${id}";
          value = {
            hostPath = config.sops.secrets."cobalt-device-${id}".path;
            isReadOnly = true;
          };
        })
        deviceIds
    ))
  ];

  containers.access-vlan8.bindMounts = lib.mkMerge [
    (lib.listToAttrs (
      map
        (id: {
          name = "/run/secrets/devices/${id}";
          value = {
            hostPath = config.sops.secrets."cobalt-device-${id}".path;
            isReadOnly = true;
          };
        })
        deviceIds
    ))
  ];

  virtualisation.qemu.networkingOptions = lib.mkForce qemuNetworkingOptions;
}
