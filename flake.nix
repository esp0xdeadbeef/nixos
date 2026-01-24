{
  description = "esp0xdeadbeef nix config";

  inputs = {
    nixpkgs-stable = {
      url = "github:nixos/nixpkgs/nixos-25.11";
    };
    nixpkgs-unstable = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };
    nixpkgs = {
      # url = "github:nixos/nixpkgs/nixos-24.11";
      url = "github:nixos/nixpkgs/nixos-25.11";
      # url = "github:nixos/nixpkgs/nixos-unstable";
    };
    systems = {
      url = "github:nix-systems/default-linux";
    };
    kickstart-nix-nvim = {
      url = "github:nix-community/kickstart-nix.nvim";
      # do NOT make nixpkgs follow your main nixpkgs; it breaks wrapNeovimUnstable
      # omit this line entirely:
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-router-vpn-gateway = {
      url = "github:esp0xdeadbeef/nixos-router-vpn-gateway";
    };
    nixvim = {
      url = "github:nix-community/nixvim";
    };
    khanelivim = {
      url = "github:khaneliman/khanelivim";
    };

    # This doesn't work:
    # obsidian-nvim = {
    #   url = "github:epwalsh/obsidian.nvim";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    # Required, nvf works best and only directly supports flakes
    nvf = {
      url = "github:NotAShelf/nvf";
      # You can override the input nixpkgs to follow your system's
      # instance of nixpkgs. This is safe to do as nvf does not depend
      # on a binary cache.
      inputs.nixpkgs.follows = "nixpkgs";
      # Optionally, you can also override individual plugins
      # for example:
      # inputs.obsidian-nvim.follows = "obsidian-nvim"; # <- this will use the obsidian-nvim from your inputs
    };

    # zen-browser = {
    #   url = "github:0xc000022070/zen-browser-flake";
    #   # IMPORTANT: we're using "libgbm" and is only available in unstable so ensure
    #   # to have it up-to-date or simply don't specify the nixpkgs input
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    # You can access packages and modules from different nixpkgs revs
    # Also see the 'unstable-packages' overlay at 'overlays/default.nix'.

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # sops:
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # hardware:
    hardware = {
      url = "github:nixos/nixos-hardware";
      # inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware = {
      url = "github:nixos/nixos-hardware";
      # inputs.nixpkgs.follows = "nixpkgs";
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
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    # nixos-x13s branch to follow:
    nixos-x13s = {
      url = "github:BrainWart/x13s-nixos";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    # integrated:
    # nix run github:Mic92/nixos-shell --  --flake .#vm
    nixos-shell = {
      url = "github:Mic92/nixos-shell";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      inherit (self) outputs;

      # Supported systems for your flake packages, shell, etc.
      systems = [
        "aarch64-linux"
        "i686-linux"
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      # This is a function that generates an attribute by calling a function you
      # pass to it, with each system as an argument
      forAllSystems = nixpkgs.lib.genAttrs systems;
      lib = nixpkgs.lib;

      # Minimal flake source for per-VM builds
      vmSourceForPath =
        relPath:
        let
          root = self.outPath;
          vmPath = "${root}/${relPath}";
        in
        if builtins.pathExists vmPath then
          builtins.path {
            name = "esp0xdeadbeef-vm-src-${builtins.replaceStrings [ "/" ] [ "-" ] relPath}";
            path = root;
            filter =
              p: _:
              lib.any (prefix: lib.hasPrefix prefix p) [
                "${root}/flake.nix"
                "${root}/flake.lock"

                # VM subtree
                "${vmPath}"

                # YOUR repo uses these top-level dirs (NOT nixos/modules)
                "${root}/nixos"
                "${root}/modules"
                "${root}/overlays"
                "${root}/pkgs"
                "${root}/home-manager"
                "${root}/secrets"
                "${root}/dev-updaters"
              ];
          }
        else
          # fallback to full flake root (still works as a path flake)
          root;
    in
    {
      lib = {
        inherit vmSourceForPath;
      };

      # Your custom packages
      # Accessible through 'nix build', 'nix shell', etc
      packages =
        if builtins.pathExists ./pkgs then
          forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system})
        else
          { };

      # Formatter for your nix files, available through 'nix fmt'
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);

      # Your custom packages and modifications, exported as overlays
      overlays = if builtins.pathExists ./overlays then import ./overlays { inherit inputs; } else { };

      # Reusable nixos modules you might want to export
      nixosModules = if builtins.pathExists ./modules/nixos then import ./modules/nixos else { };

      # Reusable home-manager modules you might want to export
      homeManagerModules =
        if builtins.pathExists ./modules/home-manager then import ./modules/home-manager else { };

      # NixOS configuration entrypoint
      # Available through 'nixos-rebuild --flake .#your-hostname'
      nixosConfigurations = {
        # test vm:
        s-test-vm = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            #lanzaboote.nixosModules.lanzaboote
            ./nixos/s-test-vm/configuration.nix
          ];
        };

        s-sigma = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs self; };
          modules = [
            #lanzaboote.nixosModules.lanzaboote
            ./nixos/server/s-sigma
          ];
        };

        s-test-vm-impermanence = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            #lanzaboote.nixosModules.lanzaboote
            ./nixos/s-test-vm-impermanence/configuration.nix
          ];
        };

        # router-core
        s-router-core = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            #lanzaboote.nixosModules.lanzaboote
            ./nixos/virtual-machine/nixos-shell-vm/s-router-core/configuration.nix
          ];
        };

        # router-edge
        s-router-edge = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            ./nixos/virtual-machine/nixos-shell-vm/s-router-edge
          ];
        };

        # x13s laptop:
        l-x13s = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            ./nixos/l-x13s/configuration.nix
          ];
        };

        # work laptop:
        l-werk = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            #lanzaboote.nixosModules.lanzaboote
            ./nixos/laptop/l-werk
          ];
        };

        # private laptop:
        l-esp = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            ./nixos/laptop/l-esp
          ];
        };

        # lxc server
        s-lxc-test = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            ./nixos/s-lxc-test/configuration.nix
          ];
        };

        s-gameserver = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            ./nixos/virtual-machine/nixos-shell-vm/s-gameserver
          ];
        };

        s-test = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            ./nixos/virtual-machine/nixos-shell-vm/s-test
          ];
        };

        s-infra = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            ./nixos/virtual-machine/nixos-shell-vm/s-infra
          ];
        };

        s-router-vpn-egress = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            ./nixos/virtual-machine/nixos-shell-vm/s-router-vpn-egress
          ];
        };

        s-more-threads-then-the-host = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            ./nixos/s-more-threads-then-the-host
          ];
        };
      };
    };
}
