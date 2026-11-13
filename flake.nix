{
  description = "esp0xdeadbeef nix config";

  inputs = {
    nixpkgs-unstable = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };

    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-26.05";
    };

    nixpkgs-25_11 = {
      url = "github:nixos/nixpkgs/release-25.11";
    };

    nixos-router-vpn-gateway = {
      url = "github:esp0xdeadbeef/nixos-router-vpn-gateway";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # The wardriving SSID wordlist used to derive plausible, boring Wi-Fi
    # SSIDs from a SOPS seed is vendored at
    # library/01-general/network/ssids.txt and read via relativeRepo, so it
    # tracks this repository rather than a removed upstream capture.

    nixos-mailserver = {
      url = "gitlab:simple-nixos-mailserver/nixos-mailserver/nixos-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Network control-plane / renderer graph.
    # network-labs is only used by s-router-nixos, which reads its lab
    # intent/inventory from the network-labs repo's active-lab directory.
    # All other network-* inputs are pinned directly here (tracking main),
    # so `nix flake update` moves them to the latest main without going
    # through network-labs.
    network-labs = {
      url = "github:esp0xdeadbeef/network-labs";
    };

    network-compiler = {
      url = "github:esp0xdeadbeef/network-compiler";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-labs.follows = "network-labs";
    };

    network-forwarding-model = {
      url = "github:esp0xdeadbeef/network-forwarding-model";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-compiler.follows = "network-compiler";
      inputs.network-labs.follows = "network-labs";
    };

    network-control-plane-model = {
      url = "github:esp0xdeadbeef/network-control-plane-model";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-forwarding-model.follows = "network-forwarding-model";
      inputs.network-labs.follows = "network-labs";
    };

    network-realization-schema = {
      url = "github:esp0xdeadbeef/network-realization-schema";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    network-realization-model = {
      url = "github:esp0xdeadbeef/network-realization-model";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-realization-schema.follows = "network-realization-schema";
    };

    network-renderer-nixos = {
      url = "github:esp0xdeadbeef/network-renderer-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-control-plane-model.follows = "network-control-plane-model";
      inputs.network-forwarding-model.follows = "network-forwarding-model";
      inputs.network-realization-model.follows = "network-realization-model";
      inputs.network-labs.follows = "network-labs";
    };

    # Testing-chain WireGuard renderer, bound to the *main* realization model.
    #
    # Consumers on a -prod chain must NOT inherit this default: their
    # `networkRealizationModelInput` is `network-realization-model-prod`, and a
    # bundle stamped by the main model fails the prod model's release check
    # closed with `NR_RENDERER_BUNDLE_UNVALIDATED`. Use
    # network-renderer-wireguard-prod below for those.
    network-renderer-wireguard = {
      url = "github:esp0xdeadbeef/network-renderer-wireguard";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-control-plane-model.follows = "network-control-plane-model";
      inputs.network-realization-model.follows = "network-realization-model";
    };

    network-renderer-nebula = {
      url = "github:esp0xdeadbeef/network-renderer-nebula";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-control-plane-model.follows = "network-control-plane-model";
      inputs.network-realization-model.follows = "network-realization-model";
      inputs.network-labs.follows = "network-labs";
    };

    network-renderer-access-endpoint-nixos = {
      url = "github:esp0xdeadbeef/network-renderer-access-endpoint-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-control-plane-model.follows = "network-control-plane-model";
      inputs.network-realization-model.follows = "network-realization-model";
      inputs.network-labs.follows = "network-labs";
    };

    # Pinned production stack (frozen: never advanced by `nix flake update`).
    # s-router-prod consumes these; s-router-neon-new tracks the same model on main.
    #
    # The prod compilers and models declare their own `network-labs` input; pin
    # it explicitly so a non-prod `network-labs` bump can never be dragged into
    # the frozen stack through the mutable root. The revs are the ones the
    # frozen stack resolved to when it was pinned (see flake.lock at the
    # commit that froze the -prod inputs).
    network-labs-prod = {
      url = "github:esp0xdeadbeef/network-labs/376614f36eecb976bb59081f5fe1610babf2b5c1";
    };

    # The prod renderer resolved to a distinct labs rev when it was pinned.
    network-labs-prod-renderer = {
      url = "github:esp0xdeadbeef/network-labs/376614f36eecb976bb59081f5fe1610babf2b5c1";
    };

    network-compiler-prod = {
      url = "github:esp0xdeadbeef/network-compiler/e9907209a790fe87a9fbe447c158f60e08ac175d";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-labs.follows = "network-labs-prod";
    };

    network-forwarding-model-prod = {
      url = "github:esp0xdeadbeef/network-forwarding-model/a86b4f60815e3488786d0bbb3e103698ef9f431c";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-compiler.follows = "network-compiler-prod";
      inputs.network-labs.follows = "network-labs-prod";
    };

    network-control-plane-model-prod = {
      url = "github:esp0xdeadbeef/network-control-plane-model/b29d872e724660c42dec5b98a38dc5b658777b5f";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-forwarding-model.follows = "network-forwarding-model-prod";
      inputs.network-labs.follows = "network-labs-prod";
    };

    network-realization-schema-prod = {
      url = "github:esp0xdeadbeef/network-realization-schema/782509c1c35c6319b0fd5a39d6658fe27a91aba3";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    network-realization-model-prod = {
      url = "github:esp0xdeadbeef/network-realization-model/a97b1a0b81796537133d3086ae77fef3084db863";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-realization-schema.follows = "network-realization-schema-prod";
    };

    nixos-network-compiler-prod = {
      url = "github:esp0xdeadbeef/nixos-network-compiler/e9907209a790fe87a9fbe447c158f60e08ac175d";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    network-renderer-nixos-prod = {
      url = "github:esp0xdeadbeef/network-renderer-nixos/c8556986b2f7add2153dffda1e5f5119303286f5";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-control-plane-model.follows = "network-control-plane-model-prod";
      inputs.network-forwarding-model.follows = "network-forwarding-model-prod";
      inputs.network-realization-model.follows = "network-realization-model-prod";
      inputs.nixos-network-compiler.follows = "nixos-network-compiler-prod";
      inputs.network-labs.follows = "network-labs-prod-renderer";
    };

    # Pinned nebula renderer for the production cobalt router.  Cobalt models
    # nebula overlays (unlike prod-network, which declares none), so the
    # prod cobalt pipeline needs a nebula renderer on the -prod chain rather
    # than following the unpinned main branch that s-router-cobalt-new uses.
    network-renderer-nebula-prod = {
      url = "github:esp0xdeadbeef/network-renderer-nebula/4013bc1573773377e07e69961d3078c3d9dd7e98";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-control-plane-model.follows = "network-control-plane-model-prod";
      inputs.network-realization-model.follows = "network-realization-model-prod";
      inputs.network-labs.follows = "network-labs-prod-renderer";
    };

    # Pinned WireGuard renderer for the production cobalt router.  Cobalt
    # models WireGuard overlays (core-vpn-onyx / core-vpn-opal), so the prod
    # cobalt pipeline needs a WireGuard renderer bound to the -prod chain.  It
    # previously fell back to the unpinned `network-renderer-wireguard`, whose
    # own `network-realization-model` input followed main -- so the prod
    # realization model (a97b1a0) validated a bundle stamped by the testing
    # model, failing closed with NR_RENDERER_BUNDLE_UNVALIDATED.
    network-renderer-wireguard-prod = {
      url = "github:esp0xdeadbeef/network-renderer-wireguard/6b583f554598d7d1567fc7776e13184eccb51ea2";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-control-plane-model.follows = "network-control-plane-model-prod";
      inputs.network-realization-model.follows = "network-realization-model-prod";
    };

    # Frozen legacy production stack: the previous s-router-prod render
    # (prod-network/current), retained as s-router-legacy-prod.
    network-labs-legacy-prod = {
      url = "github:esp0xdeadbeef/network-labs/11ac8629278d255dcc0c353858a75bf59e918bd3";
    };

    network-compiler-legacy-prod = {
      url = "github:esp0xdeadbeef/network-compiler/f4c7cbb1b0dd0ae68baf52958e9b0d1266ee52e5";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-labs.follows = "network-labs-legacy-prod";
    };

    network-forwarding-model-legacy-prod = {
      url = "github:esp0xdeadbeef/network-forwarding-model/5f6a6cd12a68650fc9fb920981ecf0d2f5dd8f73";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-compiler.follows = "network-compiler-legacy-prod";
      inputs.network-labs.follows = "network-labs-legacy-prod";
    };

    network-control-plane-model-legacy-prod = {
      url = "github:esp0xdeadbeef/network-control-plane-model/5f32cfe04b25e1619a12cd24365ac9165a648c8c";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-forwarding-model.follows = "network-forwarding-model-legacy-prod";
      inputs.network-labs.follows = "network-labs-legacy-prod";
    };

    network-realization-schema-legacy-prod = {
      url = "github:esp0xdeadbeef/network-realization-schema/782509c1c35c6319b0fd5a39d6658fe27a91aba3";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    network-realization-model-legacy-prod = {
      url = "github:esp0xdeadbeef/network-realization-model/a97b1a0b81796537133d3086ae77fef3084db863";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-realization-schema.follows = "network-realization-schema-legacy-prod";
    };

    nixos-network-compiler-legacy-prod = {
      url = "github:esp0xdeadbeef/nixos-network-compiler/f4c7cbb1b0dd0ae68baf52958e9b0d1266ee52e5";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    network-renderer-nixos-legacy-prod = {
      url = "github:esp0xdeadbeef/network-renderer-nixos/d78c529e95127bef2b19f990c1dd6faadc22f3e5";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-control-plane-model.follows = "network-control-plane-model-legacy-prod";
      inputs.network-forwarding-model.follows = "network-forwarding-model-legacy-prod";
      inputs.network-realization-model.follows = "network-realization-model-legacy-prod";
      # The renderer has TWO compiler inputs (network-compiler and
      # nixos-network-compiler); wiring only one left `network-compiler`
      # resolving through the renderer's own `network-labs` to the testing
      # branch, so the frozen legacy-prod render came out of a compiler from a
      # later generation than the rest of the legacy-prod stack.
      inputs.network-compiler.follows = "network-compiler-legacy-prod";
      inputs.nixos-network-compiler.follows = "nixos-network-compiler-legacy-prod";
      inputs.network-labs.follows = "network-labs-legacy-prod";
    };

    network-renderer-containerlab-linux-backend = {
      url = "github:esp0xdeadbeef/network-renderer-containerlab-linux-backend";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-realization-model.follows = "network-realization-model";
      inputs.network-compiler.follows = "network-compiler";
      inputs.network-forwarding-model.follows = "network-forwarding-model";
      inputs.network-control-plane-model.follows = "network-control-plane-model";
      inputs.network-labs.follows = "network-labs";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
    };

    cheat-sheets = {
      url = "github:esp0xdeadbeef/cheat.sheets";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    luz-nvim = {
      url = "github:miniluz/luz-nvim";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # sops:
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # hardware:
    # Upstream nixos-hardware, UNPINNED on purpose: flake.lock is the pin, so
    # `nix flake update nixos-hardware` moves every host at once and nothing in
    # this repo hardcodes a fork rev for hardware nobody forked.
    #
    # Two inputs below carry fork-only content and are pinned by rev; they are
    # used ONLY by the hosts that need them (see each comment).
    nixos-hardware.url = "github:NixOS/nixos-hardware";

    # Fork carrying the Banana Pi BPI-R4 Pro support (bananapi/bpi-r4-pro),
    # which upstream does not have yet (upstream bananapi/ has bpi-sm10 only).
    #
    # Used ONLY by s-nodus and s-nodus-nixos-hardware.  Everything else -- the
    # laptops and the Dell servers -- uses the upstream `nixos-hardware` above,
    # so board-specific work never lands on them.
    #
    # ddc90236 is the `bananapi-bpi-r4-pro-efi` branch: the board builds its own
    # boot chain (BL2 + FIP carrying BL31 and U-Boot with CONFIG_EFI_LOADER) and
    # boots an ESP through systemd-boot, instead of the signed vendor OpenWrt
    # firmware and its raw FIT.
    nixos-hardware-bpi-r4-pro = {
      url = "github:esp0xdeadbeef/nixos-hardware/9a51c217";
      # Share the fleet's nixpkgs rather than pulling the fork's own pin into
      # the module system as a second nixpkgs.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Same fork, but on the `x13s-pr1751-plus-bpi` branch: PR #1751's x13s
    # rework (hardware.lenovo.x13s.* options, feature-keyed kernel patch series)
    # stacked on top of the bpi-r4-pro commits above. Used ONLY by
    # l-portal-unstable, so the pinned `nixos-hardware` input above stays the
    # rollback target for every deployed host.
    #
    # The PR is still open upstream; when it merges, drop this input and point
    # `nixos-hardware` at the upstream rev instead.
    nixos-hardware-x13s = {
      url = "github:esp0xdeadbeef/nixos-hardware/cb28461df42dfba83315032e0c50a366c2184ba6";
      # Follow the fleet's nixpkgs instead of the fork's own pin. The x13s
      # module only contributes board support; pulling a second nixpkgs into the
      # module system makes `nix.registry.nixpkgs` ambiguous.
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    impermanence = {
      url = "github:nix-community/impermanence";
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # To get spotify / widevine working on a x13s laptop:
    nixos-aarch64-widevine = {
      url = "github:epetousis/nixos-aarch64-widevine";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # integrated:
    # nix run github:Mic92/nixos-shell -- --flake .#vm
    #
    # Pinned to the latest stable release tag. Upstream `main` migrated to
    # virtiofs (59c2a95) and requires `virtualisation.sharedDirectories.*.writable`,
    # which only exists in nixos-unstable. The primary `nixpkgs` input tracks
    # the stable nixos-26.05 branch, whose qemu-vm still shares via 9p, so the
    # newer module cannot evaluate here. Move back to `main` once the primary
    # nixpkgs reaches 26.11; the guard in
    # library/10-vms/nixos-shell-vm/1-helpers/vm-storage-persist.nix fails on
    # 26.11, so the migration cannot be forgotten.
    nixos-shell = {
      url = "github:Mic92/nixos-shell/2.2.0";
    };

    nixos-shell-vm-manager = {
      url = "github:esp0xdeadbeef/nixos-shell-vm-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-winddk = {
      url = "github:esp0xdeadbeef/nixos-winddk";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    pin-refresh-source = {
      url = "github:esp0xdeadbeef/nixos";
      flake = false;
    };

    # Vendor firmware for the BPI-R4 Pro 4E (MT7988A): the signed BL2 + ARM-TF
    # FIP blobs the MT7988 BootROM/BL2 need to boot at all.  They cannot be
    # built from source.  Sliced from the vendor OpenWrt SD image by
    # nixos/server/s-nodus/firmware.nix, which pins them by content hash.
    #
    # The image is large (~268 MiB) and is not redistributable, so it is NOT
    # an input here: point the flash script at a local copy (see
    # nixos/server/s-nodus/README.md).  The resulting blobs (~8 MiB) are small
    # and pinned by hash in firmware.nix.

  };

  outputs =
    { self
    , nixpkgs
    , home-manager
    , ...
    }@inputs:
    let
      lib = nixpkgs.lib;
      inherit (self) outputs;

      systems = [
        "aarch64-linux"
        "i686-linux"
        "x86_64-linux"
        "aarch64-darwin"
      ];

      forAllSystems = lib.genAttrs systems;

      root = ./.;

      repoLib = import ./library/imports.nix { inherit lib; };
      relativeRepo = import ./library/relative-repo.nix { inherit lib root; };

      profiles = import ./profiles;

      # Host architecture overrides.
      #
      # Most hosts are x86_64. The ThinkPad X13s is Qualcomm ARM64, so evaluating
      # it as x86_64-linux is wrong.
      hostSystems = {
        l-portal = "aarch64-linux";
        # Same physical X13s as l-portal, built against the PR #1751
        # nixos-hardware branch (see the `nixos-hardware-x13s` input).
        l-portal-unstable = "aarch64-linux";
        # s-nodus: Banana Pi BPI-R4 Pro 4E (MediaTek MT7988A).
        s-nodus = "aarch64-linux";
        # s-router-cobalt-new runs under KVM on s-nodus, so the guest must
        # match the board.  This is the only place its architecture is set;
        # every other VM defaults to x86_64-linux.
        s-router-cobalt-new = "aarch64-linux";
        # s-router-cobalt-prod is the prod-shaped cobalt router; it also runs
        # under KVM on s-nodus, so it must match the board.  Without this it
        # falls back to x86_64-linux, which builds an x86_64 runner wrapper
        # around an aarch64 guest: the runner dies with `Exec format error`
        # (exit 78/CONFIG) before the guest boots.
        s-router-cobalt-prod = "aarch64-linux";
        # NOTE: s-tang is intentionally absent -- Tang runs as a host container
        # on s-nodus (nixos/server/s-nodus/tang.nix) instead of a nixos-shell
        # VM, so it has no VM image and no guest architecture.
      };

      hostSystemFor = name: hostSystems.${name} or "x86_64-linux";

      # ------------------------------------------------------------
      # STRUCTURAL HOST ROOTS (semantic, stable)
      # ------------------------------------------------------------
      hostRoots = [
        "nixos/laptop"
        "nixos/server"
        "nixos/virtual-machine/nixos-shell-vm"
        "nixos/virtual-machine/dedicated-vm"
        "nixos/virtual-machine/nixos-anywhere"
      ];

      # List direct subdirectories
      listDirs =
        path:
        let
          abs = root + "/${path}";
        in
        if builtins.pathExists abs then
          lib.filterAttrs (_: v: v == "directory") (builtins.readDir abs)
        else
          { };

      # Discover all hosts automatically
      hosts = lib.foldl'
        (
          acc: base: acc // lib.mapAttrs (name: _: "${base}/${name}") (listDirs base)
        )
        { }
        hostRoots;

      repoOverlays =
        if builtins.pathExists ./overlays then
          import ./overlays
            {
              inherit inputs relativeRepo;
            }
        else
          { };

      overlaysList = builtins.attrValues repoOverlays;

    in
    {
      lib = repoLib // {
        inherit hosts;
      };

      packages =
        if builtins.pathExists ./pkgs then
          forAllSystems
            (
              system:
              let
                pkgs = import nixpkgs {
                  inherit system;
                  config = {
                    allowUnfree = true;
                    android_sdk.accept_license = true;
                  };
                  overlays = overlaysList;
                };
              in
              import ./pkgs {
                inherit pkgs system;
                inherit (pkgs) lib;
              }
            )
        else
          { };

      formatter = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.writeShellApplication {
          name = "fmt-nix-only";
          runtimeInputs = [ pkgs.nixpkgs-fmt ];
          text = ''
            if [ "$#" -eq 0 ]; then
              exec nixpkgs-fmt .
            fi

            nix_files=()
            for path in "$@"; do
              case "$path" in
                *.nix) nix_files+=("$path") ;;
              esac
            done

            if [ "''${#nix_files[@]}" -eq 0 ]; then
              echo "No .nix files supplied; skipping formatter." >&2
              exit 0
            fi

            exec nixpkgs-fmt "''${nix_files[@]}"
          '';
        }
      );

      overlays = repoOverlays;

      nixosModules = if builtins.pathExists ./modules/nixos then import ./modules/nixos else { };
      homeManagerModules =
        if builtins.pathExists ./modules/home-manager then
          import ./modules/home-manager { inherit relativeRepo; }
        else
          { };

      inherit profiles;

      # ------------------------------------------------------------
      # GENERATED NIXOS CONFIGURATIONS
      # ------------------------------------------------------------
      # Hosts built against `nixpkgs-unstable` instead of the pinned `nixpkgs`
      # (nixos-26.05). This is what makes a host genuinely unstable: its package
      # set, kernel and module system all come from nixos-unstable.
      #
      # An explicit allowlist, so no host drifts off the release pin by accident.
      # `l-portal-unstable` exists to run nixos-unstable on the X13s with board
      # support from the PR #1751 nixos-hardware branch.
      nixosConfigurations =
        let
          unstableNixpkgsHosts = [ "l-portal-unstable" ];
          nixpkgsFor =
            name:
            if lib.elem name unstableNixpkgsHosts then inputs.nixpkgs-unstable else nixpkgs;
        in
        lib.mapAttrs
        (
          name: path:
            (nixpkgsFor name).lib.nixosSystem {
              system = hostSystemFor name;

              specialArgs = {
                inherit
                  inputs
                  outputs
                  profiles
                  relativeRepo
                  self
                  name
                  ;

                # Guest architecture for this configuration.  Defaults to
                # x86_64-linux and is overridden per host/VM through
                # `hostSystems` above, so VM modules never hardcode it.
                vmSystem = hostSystemFor name;

                # VM images this host is meant to run, resolved HERE rather
                # than via `self.nixosConfigurations.<vm>` inside the host's own
                # module tree.  Referencing the attrset from within a member of
                # it is a cycle: evaluating s-nodus forces the VM image, which
                # forces nixosConfigurations, which forces s-nodus again -- and
                # it surfaces as `attribute '<vm>' missing` while building the
                # host's rootfsImage.  Computing the mapping at the flake level,
                # where nixosConfigurations is complete, cannot cycle.
                # NIC map for the cobalt router VMs, computed here for the same
                # no-cycle reason as vmImages: the hypervisor host needs to know
                # which tap belongs to which bridge (vhost NICs are rendered as
                # `-netdev tap,ifname=tap-<nicId>` and qemu does not bridge a
                # bare tap). This is the single source of truth for those NICs.
                # The host-local s-nodus carries these, and its
                # s-nodus-nixos-hardware test copy does too (same board, same VMs),
                # so neither loses its tap map.
                vmNics =
                  if lib.elem name [ "s-nodus" "s-nodus-nixos-hardware" ] then
                    {
                      s-router-cobalt-new = [
                        {
                          nicId = "lan-trunk";
                          bridge = "br-cobalt-lan";
                        }
                        {
                          nicId = "wan";
                          bridge = "br-cobalt-wan";
                        }
                      ];
                      s-router-cobalt-prod = [
                        {
                          nicId = "lan-trunk";
                          bridge = "br-cobalt-lan";
                        }
                        {
                          nicId = "wan";
                          bridge = "br-cobalt-wan";
                        }
                      ];
                    }
                  else
                    { };

                # IMPORTANT: `vmImages` is a BUILD, not a pin.
                #
                # The `*-prod` / `*-legacy-prod` inputs above are safe: their
                # URLs name exact commits, so `nix flake update` provably cannot
                # move them (verified 2026-11-07: a full `nix flake update`
                # followed by scripts/check-prod-pins.sh reports
                # "protected production pins unchanged").
                #
                # The production VM *image* is not protected by that at all. It
                # is derived from `self.nixosConfigurations.<vm>...nixos-shell`,
                # so every host rebuild rebuilds it from every input -- including
                # inputs nobody considers production, such as a transitive
                # nixpkgs. On 2026-11-07 such a bump produced a new image path,
                # the manager booted it, the guest never brought QGA up, and the
                # site lost its router while every -prod pin was untouched.
                #
                # BLOCKED: pinning the artifact needs its own rev-pinned flake
                # input for the production router config (URL naming an exact
                # commit, like the -prod inputs), because a store path literal is
                # rejected (types.package) and `builtins.storePath` makes the
                # whole flake evaluate only on a machine that already has the
                # image. Until that exists, treat any host rebuild as capable of
                # changing the production image, and verify with vm-status after.
                vmImages =
                  if lib.elem name [ "s-nodus" "s-nodus-nixos-hardware" ] then
                    {
                      s-router-cobalt-new =
                        self.nixosConfigurations.s-router-cobalt-new.config.system.build.nixos-shell;
                      # Prod cobalt router is the carrier-managed instance (see
                      # vm-host.nix); s-router-cobalt-new above is kept only as
                      # the rollback target, so its image must stay buildable.
                      #
                      # PINNED BY CONTENT. Deriving this from
                      # `self.nixosConfigurations...` meant the production image
                      # was rebuilt from every input on every host build: on
                      # 2026-11-07 a transitive bump changed its store path
                      # (7mdq7c7f -> 3ja6ivx0), the manager booted the new one,
                      # and the guest never brought QGA up -- the site lost its
                      # router while every *-prod pin was provably unchanged.
                      #
                      # This copies the known-good image into a derivation whose
                      # output path is content-addressed, so input bumps cannot
                      # move it; changing the production image requires editing
                      # the literal below. `builtins.pathExists` keeps the flake
                      # evaluable on hosts that do not hold the image (they get the
                      # derived build), so only the machine that actually runs
                      # prod is pinned.
                      s-router-cobalt-prod =
                        let
                          pinned = "/nix/store/7mdq7c7f6l9i651v8idi2lxl886js87j-nixos-vm";
                        in
                        if builtins.pathExists pinned then
                          (nixpkgs.legacyPackages.${hostSystemFor name}).runCommandLocal
                            "s-router-cobalt-prod-pinned-nixos-vm"
                            { preferredLocalBuilders = [ "@none" ]; }
                            "cp -L ${builtins.storePath pinned} $out"
                        else
                          self.nixosConfigurations.s-router-cobalt-prod.config.system.build.nixos-shell;
                    }
                  else
                    { };
              };

              modules = [
                outputs.nixosModules.pythonPycachePrefix

                (./. + "/${path}")
              ];
            }
        )
        hosts;

      # Disko configurations evaluated on the BUILD host (x86_64), not the
      # target. disko's own binaries must run on the machine doing the
      # partitioning -- evaluating them for aarch64 would ship aarch64 binaries
      # to an x86_64 host ("Exec format error").
      #
      # NOTE: disko alone does NOT produce a bootable s-nodus card (it cannot
      # write the BL2/FIP firmware blobs nor the raw NixOS FIT). Use
      # nixos/server/s-nodus/mk-sd-image.sh for the full image.
      # Card + NVMe, for building a complete card.  `disk` MUST be given: the
      # card is /dev/sda on a laptop but /dev/mmcblk0 on the board, so there is
      # no safe default.  e.g.
      #   nix run github:nix-community/disko -- \
      #     --mode destroy,format,mount --argstr disk /dev/sda \
      #     --flake .#s-nodus-disk
      #
      # Left unset here on purpose: the value is supplied at disko invocation
      # time, and the attribute is only forced when `sdcard` is actually
      # described (see disko.nix).
      diskoConfigurations.s-nodus-disk =
        (import ./nixos/server/s-nodus/disko.nix {
          inherit lib;
          disk = null;
        });

      # Root-only: describes just the NVMe.  Used to install the root filesystem
      # without touching the microSD, whose boot chain is already in place and
      # must stay intact.
      diskoConfigurations.s-nodus-root =
        (import ./nixos/server/s-nodus/disko.nix {
          inherit lib;
          disk = null;
          withSdcard = false;
        });
    };
}
