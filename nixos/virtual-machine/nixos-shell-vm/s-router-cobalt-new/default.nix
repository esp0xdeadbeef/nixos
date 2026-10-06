{ inputs
, lib
, config
, pkgs
, relativeRepo
, outputs
, ...
}:
let
  hostName = "s-router-cobalt-new";
  # aarch64: this VM is meant to run on the BPI-R4 Pro 4E (MT7988A) under
  # KVM, so it must match the host architecture.  The whole GAMP pipeline
  # (CPM, realization model, nixos/wireguard/nebula renderers) is arch-generic
  # -- `system` is threaded through as a parameter and every layer exposes
  # aarch64-linux in libBySystem -- so this is the only change required.
  # The x86_64 build of an equivalent VM is `s-router-cobalt` on l-envil.
  system = "aarch64-linux";
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

  # No per-VM secrets/<host>.yaml: this VM reuses the cobalt site's existing
  # secret files (same site, same devices), so opt out of the sops-provisioned
  # deadbeef password the nixos-shell-host base would otherwise expect at
  # secrets/s-router-cobalt-new.yaml.  Matches s-router-prod/neon/legacy-prod.
  local.users.deadbeefSops.enable = false;

  users.users.deadbeef = {
    isNormalUser = true;
    hashedPassword = "!";
    shell = pkgs.zsh;
  };

  imports = [
    outputs.nixosModules.containerNetworkDefaults

    (relativeRepo.module "library/10-vms/nixos-shell-vm/host-config-routers-without-network")

    (import ./renderers.nix {
      inherit
        inputs
        relativeRepo
        lib
        modelSource
        ;

      hostName = "s-router-cobalt-new";
      # Cobalt tracks the latest network-* main branches; s-router-prod stays
      # pinned to the -prod inputs in flake.lock for stability.
      controlPlaneModelInput = inputs.network-control-plane-model;
      networkRealizationModelInput = inputs.network-realization-model;
      nixosRendererInput = inputs.network-renderer-nixos;
      nebulaRendererInput = inputs.network-renderer-nebula;
      intentFileName = "intent-cobalt.nix";
      inventoryFileName = "inventory-cobalt.nix";
      inherit system vmNics;
      selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-cobalt-new/default.nix";
    })
  ];

  # Build/run this VM as aarch64.  `system` above is only the value threaded
  # into the GAMP renderers; host-config-routers-without-network/vm-settings.nix
  # hardcodes nixpkgs.hostPlatform = "x86_64-linux" (these VMs were designed for
  # the x86 Dell servers), so without mkForce the whole configuration is built
  # for x86_64 and the run-*-vm runner embeds x86_64 coreutils -> "Exec format
  # error" on the board.  l-portal sets hostPlatform the same way.
  nixpkgs.hostPlatform = lib.mkForce "aarch64-linux";

  # vm-settings.nix sizes every router VM for the Dell servers (42 cores,
  # 40 GiB RAM, 20 GiB disk) and attaches it to the x86-only `vmbr4` bridge.
  # The board is a 4-core/4 GiB MT7988A whose only usable interface is the
  # DSA switch port, so override both to something that fits.
  virtualisation = {
    cores = lib.mkForce 4;
    memorySize = lib.mkForce 1024;
    diskSize = lib.mkForce (8 * 1024);
    # Drop the vmbr4 NICs; nixos-shell adds the user-mode NAT NIC by default,
    # which is enough to reach the guest and for it to DHCP/build.
    qemu.networkingOptions = lib.mkForce [ "-nic none" ];
  };

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
    }
    # garnet overlay PKI + lighthouse endpoint for the cobalt core node
    # (FS-460-HDS-010-SDS-010-SMS-010). The Nebula renderer bind-mounts these
    # exact names into the core-vpn-garnet-cobalt container.
    // (lib.genAttrs
      [
        "nebula-profile-core-vpn-garnet-cobalt-ca-crt"
        "nebula-profile-core-vpn-garnet-cobalt-crt"
        "nebula-profile-core-vpn-garnet-cobalt-key"
        "garnet-lighthouse-endpoint4"
      ]
      (name: {
        sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-garnet.yaml";
        format = "yaml";
      })
    );

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
