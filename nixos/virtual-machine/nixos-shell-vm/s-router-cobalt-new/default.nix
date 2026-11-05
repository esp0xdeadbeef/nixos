{ inputs
, lib
, config
, pkgs
, relativeRepo
, outputs
, vmSystem ? "x86_64-linux"
, ...
}:
let
  hostName = "s-router-cobalt-new";
  # aarch64: this VM is meant to run on the BPI-R4 Pro 4E (MT7988A) under
  # KVM, so it must match the host architecture.  The whole GAMP pipeline
  # (CPM, realization model, nixos/wireguard/nebula renderers) is arch-generic
  # -- `system` is threaded through as a parameter and every layer exposes
  # aarch64-linux in libBySystem -- so this is the only change required.
  # The architecture is NOT hardcoded here: it defaults to x86_64-linux and is
  # overridden to aarch64-linux via `hostSystems` in flake.nix.  The x86_64
  # build of an equivalent VM is `s-router-cobalt` on l-envil.
  system = vmSystem;
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
      # vhost-net multiqueue: one virtqueue per vCPU instead of a single
      # emulated queue. The host's vhost-tap-attach unit enslaves the rendered
      # tap (tap-lan-trunk, tap-wan) into its bridge; without it the NIC comes
      # up DOWN and isolated, so this must not be enabled before that unit is
      # active (it now runs on VM start, not only at boot -- see vm-host.nix).
      #
      # Measured on s-nodus 2026-11-04, guest -> internet.
      #
      # Single TCP stream (a single flow uses one queue, so mq cannot help):
      #   plain bridge, 1 rx/1 tx queue:  91.5 112.9 111.8 104.0 MB/s  (median ~108)
      #   vhost mq,     4 rx/4 tx queues: 94.8 91.8 94.0 106.1 93.6 95.7 89.3 98.0
      #                                                               (median ~95)
      #
      # Four concurrent streams (cachefly, serialised samples 20s apart so CDN
      # throttling settles).
      # Pre-deploy build:
      #   plain bridge:  149.5 / 181.2 / 190.8 MB/s  (median 181.2  ~1.45 Gbps)
      #   vhost mq:      286.0 / 353.4 / 344.7 MB/s  (median 344.7  ~2.76 Gbps)
      # Re-measured on the deployed generation (44756bc7 / x9rsc61j), 2 samples:
      #   plain bridge:  162.7 / 165.2 MB/s          (median 164    ~1.31 Gbps)
      #   vhost mq:      281.8 / 330.4 MB/s          (median 306    ~2.45 Gbps)
      #                                              -> ~1.9x aggregate
      #
      # WAN-free measurement through the actual virtio NIC (iperf3, host ->
      # guest mgmt plane over ap-mgmt, 2026-11-05):
      #   plain bridge, 1 rx/1 tx queue : 1.71 Gbits/sec  (4 streams)
      #   vhost mq,     4 rx/4 tx queues: 1.99 Gbits/sec  (1 stream)
      #                                   3.88 Gbits/sec  (4 streams)
      #                                   4.28 Gbits/sec  (8 streams)
      # Guest confirms eth0/eth1 rx=4 tx=4. So the NIC itself gains ~2.3x on
      # parallel flows with no WAN in the path, and the board's own L2 fabric
      # does 8.84-8.97 Gbits/sec, so neither the NIC nor the box is the limit
      # of the 8 Gbps link.
      #
      # CAVEAT on all of the above: those figures are bounded by the upstream
      # path, not by this router. The bare host (no VM involved) measured
      # 1 stream 67 MB/s, 4 parallel 21.7 MB/s, 6 parallel 28.4 MB/s against
      # ovh/cachefly on 2026-11-05, i.e. more flows got *slower* in aggregate.
      # eth1/eth2 negotiate speed=10000 with 0 tx errors, so the local wiring
      # is fine and the limiter is upstream of the box. Do not read 2.45 Gbps
      # as the router ceiling; re-measure against a local target or a known
      # 8 Gbps-capable peer before drawing conclusions about router capacity.
      #
      # So: no single-stream gain (slightly worse), ~1.6x aggregate throughput
      # across parallel flows. That is the case this box exists for -- 8 Gbps of
      # WAN with many clients -- so the trade is worth taking. Do not cite
      # single-stream numbers as a reason for multiqueue.
      vhost = true;
      queues = 4;
    }
    {
      nicId = "wan";
      bridge = "br-cobalt-wan";
      # See lan-trunk above.
      vhost = true;
      queues = 4;
    }
  ];
in
{
  _module.args.sRouterProdProfile = {
    inherit modelSource;
    labSelector = null;
    productionSelector = hostName;
  };

  # Diagnostics for the testing/rollback router only. `selftest` records
  # DNS/WAN/TCP results on the persisted state disk; `ensureDnsForwarders`
  # keeps a public-resolver forwarder in the core container's unbound because
  # the modelled upstream (10.2.60.1) is unreachable and core otherwise runs as
  # a pure iterator that SERVFAILs while warming a cold root anchor. Off for
  # the production router: its intent does not model those resolvers.
  local.routerDiagnostics.selftest = true;
  local.routerDiagnostics.ensureDnsForwarders = true;

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

  # Build/run this VM for the architecture selected above (default x86_64).
  # `system` above is only the value threaded into the GAMP renderers;
  # host-config-routers-without-network/vm-settings.nix hardcodes
  # nixpkgs.hostPlatform = "x86_64-linux" (these VMs were designed for the x86
  # Dell servers), so without mkForce the whole configuration is built for
  # x86_64 and the run-*-vm runner embeds x86_64 coreutils -> "Exec format
  # error" on the board.  l-portal sets hostPlatform the same way.
  nixpkgs.hostPlatform = lib.mkForce system;

  # vm-settings.nix sizes every router VM for the Dell servers (42 cores,
  # 40 GiB RAM, 20 GiB disk) and attaches it to the x86-only `vmbr4` bridge.
  # The board is a 4-core/4 GiB MT7988A, so override both to fit.
  #
  # NOTE: the QEMU NIC list is NOT set here.  The NixOS renderer owns
  # virtualisation.qemu.networkingOptions (FS-982-SMS-130) and emits it from
  # the `vmNics` platform binding above (lan-trunk -> br-cobalt-lan,
  # wan -> br-cobalt-wan).  Setting it here as well would duplicate the NICs.
  virtualisation = {
    cores = lib.mkForce 4;
    # 2 GiB is the guest's *maximum*: virtio-balloon (below) lets the host
    # reclaim the pages the guest is not using, so the guest can grow up to 2 GiB
    # but only occupies what it needs.  Without ballooning a fixed 2 GiB left the
    # 4 GiB host thrashing during forwarding.
    memorySize = lib.mkForce (1024 * 2);
    diskSize = lib.mkForce (8 * 1024);
    # virtio-balloon with free-page-reporting: the guest reports freed pages and
    # the host gets that RAM back automatically, so no fixed ballooning target
    # has to be guessed -- the guest shrinks/grows with its real working set.
    qemu.options = [
      "-device virtio-balloon-pci,free-page-reporting=on"
    ];
  };

  system.stateVersion = lib.mkForce "26.05";

  sops.secrets =
    (lib.listToAttrs (
      map
        (id: {
          name = "cobalt-device-${id}";
          value = {
            sopsFile = "${deviceSopsDir}/${id}.sops.yaml";
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
