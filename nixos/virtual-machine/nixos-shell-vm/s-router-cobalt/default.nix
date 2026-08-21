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

  # The cobalt WAN uplink spoofs the ISP CPE's WAN MAC so it can replace the
  # ISP router directly on the ONT. The MAC is a SOPS secret (plan §6: not
  # committed). Apply it to eth1 (the br-cobalt-wan virtio NIC) before
  # systemd-networkd creates eth1.300 / br-wan, so the VLAN subinterface and
  # the bridge inherit it and the WAN DHCP DISCOVER carries it.
  systemd.services.cobalt-wan-mac = {
    description = "Apply spoofed WAN MAC to eth1 before networkd";
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
        if ip link show eth1 >/dev/null 2>&1; then
          ip link set dev eth1 down || true
          ip link set dev eth1 address "$mac"
          exit 0
        fi
        sleep 0.25
      done

      echo "[network] ERROR: eth1 did not appear before networkd startup" >&2
      exit 1
    '';
  };

  systemd.services.systemd-networkd = {
    after = [ "cobalt-wan-mac.service" ];
    requires = [ "cobalt-wan-mac.service" ];
  };

  virtualisation.qemu.networkingOptions = lib.mkForce qemuNetworkingOptions;
}
