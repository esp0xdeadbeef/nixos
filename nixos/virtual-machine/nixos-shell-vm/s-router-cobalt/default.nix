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

  # The ALFA AP needs the rt2800usb firmware (rt2870/rt3070).
  hardware.enableAllFirmware = true;

  imports = [
    ./ap.nix

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
      inherit system;
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
    // {
      "cobalt-onyx-private-key" = {
        sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-vpn-onyx-fields.yaml";
        key = "privateKey";
        path = "/run/secrets/onyx-private-key";
      };

      "cobalt-onyx-endpoint" = {
        sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-vpn-onyx-fields.yaml";
        key = "endpoint";
        path = "/run/secrets/onyx-endpoint";
      };

      "cobalt-onyx-preshared-key" = {
        sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-vpn-onyx-fields.yaml";
        key = "presharedKey";
        path = "/run/secrets/onyx-preshared-key";
      };

      "cobalt-onyx-public-key" = {
        sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-vpn-onyx-fields.yaml";
        key = "publicKey";
        path = "/run/secrets/onyx-public-key";
      };

      "cobalt-onyx-address" = {
        sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-vpn-onyx-fields.yaml";
        key = "address";
        path = "/run/secrets/onyx-address";
      };

      "cobalt-onyx-dns" = {
        sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-vpn-onyx-fields.yaml";
        key = "dns";
        path = "/run/secrets/onyx-dns";
      };

      "cobalt-opal-private-key" = {
        sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-vpn-opal-fields.yaml";
        key = "privateKey";
        path = "/run/secrets/opal-private-key";
      };

      "cobalt-opal-endpoint" = {
        sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-vpn-opal-fields.yaml";
        key = "endpoint";
        path = "/run/secrets/opal-endpoint";
      };

      "cobalt-opal-preshared-key" = {
        sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-vpn-opal-fields.yaml";
        key = "presharedKey";
        path = "/run/secrets/opal-preshared-key";
      };

      "cobalt-opal-public-key" = {
        sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-vpn-opal-fields.yaml";
        key = "publicKey";
        path = "/run/secrets/opal-public-key";
      };

      "cobalt-opal-address" = {
        sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-vpn-opal-fields.yaml";
        key = "address";
        path = "/run/secrets/opal-address";
      };

      "cobalt-opal-dns" = {
        sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-vpn-opal-fields.yaml";
        key = "dns";
        path = "/run/secrets/opal-dns";
      };

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

  containers.access-clients.bindMounts = lib.mkMerge [
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

  containers.access-iot.bindMounts = lib.mkMerge [
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

  # The cobalt WAN DHCP client runs inside the `core` container on its `wan`
  # veth (attached to br-wan). The ISP binds the service to the CPE's WAN
  # MAC, so that veth must advertise the cloned MAC (plan §6: SOPS secret,
  # not committed). Apply it in the core container before its
  # systemd-networkd starts DHCP on the interface.
  containers.core.bindMounts."/run/secrets/cobalt-wan-mac" = {
    hostPath = config.sops.secrets."cobalt-wan-mac".path;
    isReadOnly = true;
  };

  containers.core.config = {
    systemd.services.core-wan-mac = {
      description = "Apply spoofed WAN MAC to wan before networkd";
      wantedBy = [ "sysinit.target" ];
      before = [ "systemd-networkd.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.iproute2
      ];
      script = ''
        set -euo pipefail

        macSecret="/run/secrets/cobalt-wan-mac"
        if [ ! -r "$macSecret" ]; then
          echo "[network] ERROR: $macSecret is not readable" >&2
          exit 1
        fi

        mac="$(tr -d '[:space:]' < "$macSecret")"
        if ! printf '%s\n' "$mac" | grep -Eq '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'; then
          echo "[network] ERROR: $macSecret does not contain a valid MAC address" >&2
          exit 1
        fi

        for _ in $(seq 1 40); do
          if ip link show wan >/dev/null 2>&1; then
            ip link set dev wan down || true
            ip link set dev wan address "$mac"
            exit 0
          fi
          sleep 0.25
        done

        echo "[network] ERROR: wan did not appear before networkd startup" >&2
        exit 1
      '';
    };

    systemd.services.systemd-networkd = {
      after = [ "core-wan-mac.service" ];
      requires = [ "core-wan-mac.service" ];
    };
  };

  virtualisation.qemu.networkingOptions = lib.mkForce qemuNetworkingOptions;

  # The 14 router containers all boot in parallel on VM start. Under that
  # parallel CPU/IO load a single container's systemd boot can exceed the
  # nixpkgs default TimeoutStartSec of 1 minute, which makes systemd-nspawn
  # time out and restart the container in a loop. Give them a generous start
  # timeout so a cold boot completes without the restart storm.
  containers.access-clients.timeoutStartSec = "10min";
  containers.access-clients-vpn.timeoutStartSec = "10min";
  containers.access-dmz.timeoutStartSec = "10min";
  containers.access-iot.timeoutStartSec = "10min";
  containers.access-iot-srv.timeoutStartSec = "10min";
  containers.access-mgmt.timeoutStartSec = "10min";
  containers.access-svc.timeoutStartSec = "10min";
  containers.access-unlock.timeoutStartSec = "10min";
  containers.core.timeoutStartSec = "10min";
  containers.core-vpn-onyx.timeoutStartSec = "10min";
  containers.core-vpn-opal.timeoutStartSec = "10min";
  containers.downstream-selector.timeoutStartSec = "10min";
  containers.policy.timeoutStartSec = "10min";
  containers.upstream-selector.timeoutStartSec = "10min";
}
