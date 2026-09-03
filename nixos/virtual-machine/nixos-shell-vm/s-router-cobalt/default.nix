{ inputs
, lib
, config
, pkgs
, relativeRepo
, outputs
, ...
}:
let
  hostName = "s-router-cobalt";
  system = "x86_64-linux";
  modelSource = relativeRepo.sourcePath "prod-network/testing";
  deviceDir = relativeRepo.sourcePath "prod-network/testing/secrets/devices";
  deviceIds =
    map
      (name: lib.removeSuffix ".sops.yaml" name)
      (builtins.filter
        (name: lib.hasSuffix ".sops.yaml" name)
        (builtins.attrNames (builtins.readDir deviceDir)));

  # The access containers that publish the per-device MAC reservations to
  # their DHCP server.
  deviceSecretAccessContainers = [
    "access-clients"
    "access-iot"
  ];

  vpnFields = [
    { field = "privateKey"; path = "private-key"; }
    { field = "endpoint"; path = "endpoint"; }
    { field = "presharedKey"; path = "preshared-key"; }
    { field = "publicKey"; path = "public-key"; }
    { field = "address"; path = "address"; }
    { field = "dns"; path = "dns"; }
  ];

  vpnSecrets = name: entry: {
    name = "cobalt-${name}-${entry.path}";
    value = {
      sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-vpn-${name}-fields.yaml";
      key = entry.field;
      path = "/run/secrets/${name}-${entry.path}";
    };
  };

  vmNics = [
    {
      nicId = "lan-trunk";
      bridge = "br-cobalt-lan";
    }
    {
      nicId = "wan";
      bridge = "br-cobalt-wan";
    }
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
    outputs.nixosModules.containerNetworkDefaults

    (relativeRepo.module "library/10-vms/nixos-shell-vm/host-config-routers-without-network")

    (import ../s-router-prod/renderers.nix {
      inherit
        inputs
        lib
        modelSource
        ;

      hostName = "s-router-cobalt";
      # Cobalt tracks the latest network-* main branches; s-router-prod stays
      # pinned to the -prod inputs in flake.lock for stability.
      controlPlaneModelInput = inputs.network-control-plane-model;
      networkRealizationModelInput = inputs.network-realization-model;
      nixosRendererInput = inputs.network-renderer-nixos;
      intentFileName = "intent-cobalt.nix";
      inventoryFileName = "inventory-cobalt.nix";
      inherit system vmNics;
      selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-cobalt/default.nix";
    })
  ];

  system.stateVersion = lib.mkForce "26.05";

  sops.secrets =
    (lib.listToAttrs (
      map
        (id: {
          name = "cobalt-device-${id}";
          value = {
            sopsFile = "${deviceDir}/${id}.sops.yaml";
            key = "mac";
            format = "yaml";
            path = "/run/secrets/devices/${id}";
          };
        })
        deviceIds
    ))
    // (lib.listToAttrs (
      builtins.concatMap
        (name: map (vpnSecrets name) vpnFields)
        [ "onyx" "opal" ]
    ))
    // {
      "cobalt-wifi" = {
        sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-wifi.yaml";
        key = "";
        path = "/run/secrets/cobalt-wifi";
      };

      "cobalt-wan-mac" = {
        sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-wan-mac.yaml";
        key = "mac";
        format = "yaml";
        path = "/run/secrets/cobalt-wan-mac";
      };
    };

  # The DHCP servers in the access containers read the per-device MAC
  # reservations from the host's SOPS materialization.
  containers = lib.mkMerge [
    (lib.genAttrs deviceSecretAccessContainers (name: {
      bindMounts = lib.mkMerge [
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
    }))

    {
      # The renderer's s88-link-init service applies the cloned WAN MAC inside
      # the core container; the host only delivers the SOPS secret via the
      # bind mount.
      core.bindMounts."/run/secrets/cobalt-wan-mac" = {
        hostPath = config.sops.secrets."cobalt-wan-mac".path;
        isReadOnly = true;
      };
    }
  ];
}
