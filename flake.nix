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

    # Raw wardriving SSID list (Bronyte/Wifi-Names); used to derive
    # plausible, boring Wi-Fi SSIDs from a SOPS seed instead of hardcoding
    # recognizable names. flake = false so only the tree is fetched.
    wifi-ssids = {
      url = "github:Bronyte/Wifi-Names";
      flake = false;
    };

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

    nixos-network-compiler = {
      url = "github:esp0xdeadbeef/nixos-network-compiler";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-labs.follows = "network-labs";
    };
    network-renderer-nixos = {
      url = "github:esp0xdeadbeef/network-renderer-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixos-network-compiler.follows = "nixos-network-compiler";
      inputs.network-control-plane-model.follows = "network-control-plane-model";
      inputs.network-forwarding-model.follows = "network-forwarding-model";
      inputs.network-realization-model.follows = "network-realization-model";
      inputs.network-labs.follows = "network-labs";
    };

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

    network-compiler-prod = {
      url = "github:esp0xdeadbeef/network-compiler/6c513bbc4cb0d5f73690d4164a92a01544e90c2e";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    network-forwarding-model-prod = {
      url = "github:esp0xdeadbeef/network-forwarding-model/1136741a313e3b8b0d5433dcf7fec4984d2a6619";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-compiler.follows = "network-compiler-prod";
    };

    network-control-plane-model-prod = {
      url = "github:esp0xdeadbeef/network-control-plane-model/6f0bbc650470637cd8d1c4962c3f6f4a45f21b4e";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-forwarding-model.follows = "network-forwarding-model-prod";
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
      url = "github:esp0xdeadbeef/nixos-network-compiler/6c513bbc4cb0d5f73690d4164a92a01544e90c2e";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    network-renderer-nixos-prod = {
      url = "github:esp0xdeadbeef/network-renderer-nixos/7264bd5b68b41dbfc701be47684e31ed033f4a4d";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-control-plane-model.follows = "network-control-plane-model-prod";
      inputs.network-forwarding-model.follows = "network-forwarding-model-prod";
      inputs.network-realization-model.follows = "network-realization-model-prod";
      inputs.nixos-network-compiler.follows = "nixos-network-compiler-prod";
    };

    network-compiler-legacy-prod = {
      url = "github:esp0xdeadbeef/network-compiler/f267ab67b86641bfed59f4a5fe6d4c92b7535773";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    network-forwarding-model-legacy-prod = {
      url = "github:esp0xdeadbeef/network-forwarding-model/97fa4f97681827c9848bb79e6b32a19c1756498f";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-compiler.follows = "network-compiler-legacy-prod";
    };

    network-control-plane-model-legacy-prod = {
      url = "github:esp0xdeadbeef/network-control-plane-model/5029a38f9feed2f97d855a7425e66b797787824e";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-forwarding-model.follows = "network-forwarding-model-legacy-prod";
    };

    nixos-network-compiler-legacy-prod = {
      url = "github:esp0xdeadbeef/nixos-network-compiler/f267ab67b86641bfed59f4a5fe6d4c92b7535773";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    network-renderer-nixos-legacy-prod = {
      url = "github:esp0xdeadbeef/network-renderer-nixos/85d433856bc601a91d0e007ebf095eda41ab624a";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-control-plane-model.follows = "network-control-plane-model-legacy-prod";
      inputs.network-forwarding-model.follows = "network-forwarding-model-legacy-prod";
      inputs.nixos-network-compiler.follows = "nixos-network-compiler-legacy-prod";
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
    nixos-hardware = {
      url = "github:nixos/nixos-hardware";
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
    nixos-shell = {
      url = "github:Mic92/nixos-shell";
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

      overlaysList = builtins.attrValues (builtins.removeAttrs repoOverlays [ "impermanence-module" ]);

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
      nixosConfigurations = lib.mapAttrs
        (
          name: path:
            nixpkgs.lib.nixosSystem {
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
              };

              modules = [
                outputs.nixosModules.pythonPycachePrefix
                (./. + "/${path}")
              ];
            }
        )
        hosts;
    };
}
