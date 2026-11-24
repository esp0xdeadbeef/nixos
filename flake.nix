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

    # Network/infrastructure diagrams, via profiles.nixos.topology.
    #
    # nix-topology is a NixOS *module*, not a CLI: it has no runnable app and
    # no standalone command, so the only entrypoint is a build output of a
    # configuration that imports it --
    #   nix build .#nixosConfigurations.<host>.config.topology.output
    # Rendered by the evaluating machine (graphviz/elk), so it works for the
    # aarch64 hosts from an x86_64 workstation without an aarch64 builder.
    #
    # Only the hosts importing profiles.nixos.topology depend on this input;
    # nothing else in the fleet evaluates it.
    nix-topology = {
      url = "github:oddlama/nix-topology";
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
    # The pin is a SQUASHED single commit (`bananapi/bpi-r4-pro: init`) on the
    # `bananapi-bpi-r4-pro-upstream` branch, which is the head of upstream PR
    # https://github.com/NixOS/nixos-hardware/pull/2124 and is based on
    # upstream master, so the module content is identical to the 37-commit
    # `bananapi-bpi-r4-pro-efi` development branch it was collapsed from --
    # just with the debugging history (`fix(...)` rounds and three `BLOCKED`
    # commits recording dead ends) not shipped.  The reasoning those commits
    # carried lives in the module's own comments instead.
    #
    # The board builds its own boot chain (BL2 + FIP carrying BL31 and U-Boot
    # with CONFIG_EFI_LOADER) and boots an ESP through systemd-boot, instead of
    # the signed vendor OpenWrt firmware and its raw FIT.
    nixos-hardware-bpi-r4-pro = {
      url = "github:esp0xdeadbeef/nixos-hardware/7d2eddcc64c65109ef2795a712498d67aaa73ba9";
      # Share the fleet's nixpkgs rather than pulling the fork's own pin into
      # the module system as a second nixpkgs.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Same fork, but on the `x13s-bluetooth-mac-race` branch: PR #1751's x13s
    # rework (hardware.lenovo.x13s.* options, feature-keyed kernel patch series)
    # plus the Bluetooth MAC race fix. Used ONLY by l-portal-unstable, so the
    # pinned `nixos-hardware` input above stays the rollback target for every
    # deployed host.
    #
    # NOTE: this branch still carries the OLD 2-commit pre-EFI version of
    # bananapi/bpi-r4-pro (board support + README only -- no efi.nix/fip.nix/
    # atf.nix, none of the reboot fixes), because it branched before the EFI
    # rework.  Harmless today: l-portal-unstable never imports that module, so
    # the stale copy is dead weight in the flake graph.  It is NOT the same
    # module the `nixos-hardware-bpi-r4-pro` input above pins.
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

      # Host architecture.
      #
      # Most hosts are x86_64, so a host only states a system when that would be
      # wrong (the X13s is Qualcomm ARM64; the cobalt router VMs run under KVM on
      # an aarch64 board). The declaration lives next to the host in
      # `<host>/system.nix`, so flake.nix does not accumulate host names:
      #
      #   <host>/system.nix   { system = "aarch64-linux"; }
      #
      # Optional; the default is x86_64-linux.
      hostSystemFor =
        path:
        let
          f = root + "/${path}/system.nix";
        in
        if builtins.pathExists f then (import f).system or "x86_64-linux" else "x86_64-linux";

      # A host may also state which nixpkgs tree it is built from:
      #
      #   <host>/nixpkgs.nix   { nixpkgs = "nixpkgs-unstable"; }
      #
      # Optional; the default is the flake's release-pinned `nixpkgs`.
      hostDecl =
        file:
        path:
        let
          f = root + "/${path}/${file}";
        in
        if builtins.pathExists f then import f else { };

      # Every nixpkgs tree this flake carries, discovered rather than listed: a
      # nixpkgs input exposes both `lib` and `legacyPackages`. Adding a pin to
      # `inputs` makes it selectable with no edit here.
      #
      # `home-manager` matches that shape too but is a downstream *consumer* of
      # nixpkgs, not a tree to build a host from, so it is excluded by name.
      nixpkgsInputs = lib.filterAttrs
        (
          inputName: input:
          inputName != "home-manager" && lib.isAttrs input && input ? lib && input ? legacyPackages
        )
        inputs;

      # A host's tree must also provide its *module system*: NixOS evaluates its
      # options with `lib` from the tree that supplies `nixosSystem`, while
      # `pkgs` comes from `nixpkgs.pkgs`. Mixing the two -- unstable packages
      # under the 26.05 module system -- fails deep inside NixOS (e.g.
      # `lib.services.configure` receiving `lib` from one nixpkgs and `pkgs`
      # from another, where `importService` does not exist). The selection
      # therefore happens here, before instantiation.
      #
      # The host still decides; this only reads the decision.
      # The nixpkgs input a host selects, defaulting to the primary tree.
      hostNixpkgsInput = path: (hostDecl "nixpkgs.nix" path).nixpkgs or "stable";

      nixpkgsFor =
        path:
        let
          selected = hostNixpkgsInput path;
        in
        if selected == "stable" then
          nixpkgs
        else if nixpkgsInputs ? ${selected} then
          nixpkgsInputs.${selected}
        else
          throw "unknown nixpkgs input '${selected}' (known: stable, ${lib.concatStringsSep ", " (builtins.attrNames nixpkgsInputs)})";

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
      # One configuration per discovered host directory, host-agnostic.
      #
      # The *whole* `nixosSystem` comes from the tree the host selects, not just
      # its package set: NixOS evaluates its options with `lib` from the tree
      # that supplied `nixosSystem`, so pointing only `nixpkgs.pkgs` at another
      # nixpkgs mixes two module systems and fails deep inside NixOS (a service
      # defined by one nixpkgs being built with the other's `lib.services`).
      # Taking `lib` and `pkgs` from the same tree is the only consistent
      # arrangement; see `nixpkgsFor` above.
      nixosConfigurations =
        lib.mapAttrs
          (
            name: path:
              (nixpkgsFor path).lib.nixosSystem {
                system = hostSystemFor path;

                specialArgs = {
                  inherit
                    inputs
                    outputs
                    profiles
                    relativeRepo
                    self
                    name
                    ;

                  # Whether this host is built from something other than the
                  # flake's primary nixpkgs. Modules need to know: a host on an
                  # alternate tree must not also act as that tree's registry
                  # source (see profiles/nixos/nixpkgs/alternate-tree.nix).
                  usesAlternateNixpkgs = hostNixpkgsInput path != "stable";

                  # Guest architecture for this configuration.  Defaults to
                  # x86_64-linux and is overridden per host/VM through
                  # `<host>/system.nix`, so VM modules never hardcode it.
                  vmSystem = hostSystemFor path;

                  # Every nixos-shell VM image this flake defines, keyed by VM
                  # name, computed HERE rather than via
                  # `self.nixosConfigurations.<vm>` from inside a hypervisor's own
                  # module tree. `specialArgs` is resolved before module
                  # evaluation, so a hypervisor module reaching into that attrset
                  # would re-enter it and fail with `attribute '<vm>' missing`
                  # while building its rootfsImage. Building the mapping from the
                  # complete attrset cannot cycle.
                  #
                  # This is generic and names no host: which VMs a hypervisor
                  # actually runs, and on which bridge, is declared by that host
                  # (s-nodus: ./vm-host.nix and ./vm-images.nix, the latter also
                  # carrying the content-pinned production image).
                  derivedVmImages = lib.mapAttrs
                    (_vm: cfg: cfg.config.system.build.nixos-shell)
                    (lib.filterAttrs (_vm: cfg: cfg.config.system.build ? nixos-shell) self.nixosConfigurations);
                };

                modules = [
                  # Applies to every host, and is inert unless the host is built
                  # from a non-primary nixpkgs tree (see the module's comment).
                  profiles.nixos.nixpkgs.alternate-tree

                  (./. + "/${path}")
                ];
              }
          )
          hosts;

    };
}
