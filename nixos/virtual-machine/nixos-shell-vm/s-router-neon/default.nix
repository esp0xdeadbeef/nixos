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
  modelSource = relativeRepo.sourceModule "prod-network/testing";
  # Eval-time directory listing (readDir): needs a real path (sourceModule).
  deviceDir = relativeRepo.sourceModule "prod-network/testing/secrets/devices";
  # Build-time sops inputs: keep the fileset snapshot (sourcePath) so the
  # generated sops manifest records the same store paths as before.
  deviceSopsDir = relativeRepo.sourcePath "prod-network/testing/secrets/devices";
  deviceIds =
    map
      (name: lib.removeSuffix ".sops.yaml" name)
      (builtins.filter
        (name: lib.hasSuffix ".sops.yaml" name)
        (builtins.attrNames (builtins.readDir deviceDir)));
  vmNics = [
    {
      nicId = "lan-trunk";
      bridge = "vmbr4";
    }
    {
      nicId = "wan";
      bridge = "vmbr1";
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
    (modelSource + "/runtime-secrets.nix")

    (import ./renderers.nix {
      inherit
        inputs
        relativeRepo
        lib
        modelSource
        ;

      hostName = hostName;
      controlPlaneModelInput = inputs.network-control-plane-model;
      networkRealizationModelInput = inputs.network-realization-model;
      nixosRendererInput = inputs.network-renderer-nixos;
      nebulaRendererInput = inputs.network-renderer-nebula;
      intentFileName = "intent-neon.nix";
      inventoryFileName = "inventory-neon.nix";
      inherit vmNics;
      system = "x86_64-linux";
      selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-neon/default.nix";
    })
  ];

  system.stateVersion = lib.mkForce "26.05";

  # Per-device protected DHCP reservations (MACs). Encrypted to l-esp and
  # s-router-neon; bound into the access containers so kea can serve the
  # static vlan2 leases without the legacy full-lease JSON exports.
  sops.secrets =
    lib.listToAttrs
      (
        map
          (id: {
            name = "neon-device-${id}";
            value = {
              sopsFile = "${deviceSopsDir}/${id}.sops.yaml";
              key = "mac";
              format = "yaml";
              path = "/run/secrets/devices/${id}";
            };
          })
          deviceIds
      )
    // {
      "neon-lan-trunk-mac" = {
        sopsFile = relativeRepo.sourcePath "secrets/s-router-neon-vm-macs.yaml";
        key = "lan-trunk";
        format = "yaml";
        path = "/run/secrets/neon-lan-trunk-mac";
      };

      "neon-wan-mac" = {
        sopsFile = relativeRepo.sourcePath "secrets/s-router-neon-vm-macs.yaml";
        key = "wan";
        format = "yaml";
        path = "/run/secrets/neon-wan-mac";
      };
    }
    # garnet overlay PKI + lighthouse endpoint for the neon core node
    # (FS-460-HDS-010-SDS-010-SMS-010). The Nebula renderer bind-mounts these
    # exact names into the core-vpn-garnet-neon container.
    // (lib.genAttrs
      [
        "nebula-profile-core-vpn-garnet-neon-ca-crt"
        "nebula-profile-core-vpn-garnet-neon-crt"
        "nebula-profile-core-vpn-garnet-neon-key"
        "garnet-lighthouse-endpoint4"
      ]
      (name: {
        sopsFile = relativeRepo.sourcePath "secrets/s-router-neon-garnet.yaml";
        format = "yaml";
      })
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

  containers.access-vlan3.bindMounts = lib.listToAttrs (
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

  # The QEMU NICs receive random MACs; the stable per-NIC identities live in
  # SOPS and are applied before networkd creates the trunk/WAN bridges so the
  # bridge and VLAN interfaces inherit them.
  systemd.services.s-router-neon-vm-nic-macs = {
    description = "Apply SOPS-backed VM NIC MACs before networkd";
    wantedBy = [ "systemd-networkd.service" ];
    before = [ "systemd-networkd.service" ];
    requires = [ "sops-nix.service" ];
    after = [ "sops-nix.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail
      ${pkgs.iproute2}/bin/ip link set dev eth0 address "$(cat /run/secrets/neon-lan-trunk-mac)"
      ${pkgs.iproute2}/bin/ip link set dev eth1 address "$(cat /run/secrets/neon-wan-mac)"
    '';
  };
}
