{
  description = "esp0xdeadbeef nix config";

  inputs = {

    # # Nix ecosystem
    # Nixpkgs
    nixpkgs-stable = {
      url = "github:nixos/nixpkgs/nixos-25.05";
    };
    nixpkgs-unstable = {
      # url = "github:nixos/nixpkgs/nixos-24.11";
      url = "github:nixos/nixpkgs/nixos-unstable";
    };
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-24.11";
      # url = "github:nixos/nixpkgs/nixos-25.05";
    };
    systems = {
      url = "github:nix-systems/default-linux";
    };

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
    impermanence = {
      url = "github:nix-community/impermanence";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      lanzaboote,
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
    in
    {
      # Your custom packages
      # Accessible through 'nix build', 'nix shell', etc
      packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});
      # Formatter for your nix files, available through 'nix fmt'
      # Other options beside 'alejandra' include 'nixpkgs-fmt'
      # formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);

      # Your custom packages and modifications, exported as overlays
      overlays = import ./overlays { inherit inputs; };
      # Reusable nixos modules you might want to export
      # These are usually stuff you would upstream into nixpkgs
      nixosModules = import ./modules/nixos;

      # Reusable home-manager modules you might want to export
      # These are usually stuff you would upstream into home-manager
      homeManagerModules = import ./modules/home-manager;

      # NixOS configuration entrypoint
      # Available through 'nixos-rebuild --flake .#your-hostname'
      nixosConfigurations = {
        # test vm:
        s-test-vm = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            # required for secure boot:
            lanzaboote.nixosModules.lanzaboote
            # > Our main nixos configuration file <
            ./nixos/s-test-vm/configuration.nix
          ];
        };
        s-test-vm-impermanence = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            # required for secure boot:
            lanzaboote.nixosModules.lanzaboote

            # > Our main nixos configuration file <
            ./nixos/s-test-vm-impermanence/configuration.nix
          ];
        };
        s-test-vm-impermanence-2 = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            # required for secure boot:
            lanzaboote.nixosModules.lanzaboote

            # > Our main nixos configuration file <
            ./nixos/s-test-vm-impermanence-2/configuration.nix
          ];
        };
        s-router-vpn-1 = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            # required for secure boot:
            lanzaboote.nixosModules.lanzaboote
            # > Our main nixos configuration file <
            ./nixos/s-router-vpn-1/configuration.nix
          ];
        };
        # x13s laptop:
        l-x13s = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            # > Our main nixos configuration file <
            ./nixos/l-x13s/configuration.nix
          ];
        };
        # work laptop:
        l-werk = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            lanzaboote.nixosModules.lanzaboote
            # > Our main nixos configuration file <
            ./nixos/l-werk/configuration.nix
          ];
        };
        # private (amd) laptop:
        l-esp = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            lanzaboote.nixosModules.lanzaboote
            # > Our main nixos configuration file <
            ./nixos/l-esp/configuration.nix
          ];
        };
        # lxc server
        s-lxc-test = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            # lanzaboote.nixosModules.lanzaboote
            # > Our main nixos configuration file <
            ./nixos/s-lxc-test/configuration.nix
          ];
        };
      };
    };
}
