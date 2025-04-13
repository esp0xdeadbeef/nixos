{
  description = "esp0xdeadbeef nix config";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    # You can access packages and modules from different nixpkgs revs
    # at the same time. Here's an working example:
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    # nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-24.11";
    # Also see the 'unstable-packages' overlay at 'overlays/default.nix'.

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home manager
    home-manager.url = "github:nix-community/home-manager/release-24.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # sops:
    sops-nix = {
      url = "github:Mic92/sops-nix";
    };

    # (hardware related inputs) x13s:
    nixos-aarch64-widevine.url = "github:epetousis/nixos-aarch64-widevine";
    nixos-x13s.url = "github:BrainWart/x13s-nixos";

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
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

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
      };

      # Standalone home-manager configuration entrypoint
      # Available through 'home-manager --flake .#your-username@your-hostname'
      # NIXPKGS_ALLOW_UNFREE=1 home-manager switch --flake path:.#$(whoami)@$(hostname)
      # homeConfigurations = {
      #   # FIXME replace with your username@hostname
      #   "deadbeef@l-werk" = home-manager.lib.homeManagerConfiguration {
      #     pkgs = nixpkgs.legacyPackages.x86_64-linux; # Home-manager requires 'pkgs' instance
      #     extraSpecialArgs = { inherit inputs outputs; };
      #     modules = [
      #       # > Our main home-manager configuration file <
      #       ./home-manager/l-werk/home.nix
      #       # ./backup-of-old-nixos/hosts/home-manager/l-werk/home.nix
      #       #../../backup-of-old-nixos/hosts/network/hostname.nix
      #       # ./backup-of-old-nixos/hosts/desktop/darkmode.nix
      #     ];
      #   };
      #   # FIXME replace with your username@hostname
      #   "deadbeef@l-esp" = home-manager.lib.homeManagerConfiguration {
      #     pkgs = nixpkgs.legacyPackages.x86_64-linux; # Home-manager requires 'pkgs' instance
      #     extraSpecialArgs = { inherit inputs outputs; };
      #     modules = [
      #       # > Our main home-manager configuration file <
      #       ./home-manager/l-esp/home.nix
      #       # ./backup-of-old-nixos/hosts/home-manager/l-werk/home.nix
      #       #../../backup-of-old-nixos/hosts/network/hostname.nix
      #       # ./backup-of-old-nixos/hosts/desktop/darkmode.nix
      #     ];
      #   };
      #   "deadbeef@s-test-vm" = home-manager.lib.homeManagerConfiguration {
      #     pkgs = nixpkgs.legacyPackages.x86_64-linux; # Home-manager requires 'pkgs' instance
      #     extraSpecialArgs = { inherit inputs outputs; };
      #     modules = [
      #       # > Our main home-manager configuration file <
      #       ./home-manager/s-test-vm/home.nix
      #       # ./home-manager/l-werk/home.nix
      #       # ./backup-of-old-nixos/hosts/home-manager/l-werk/home.nix
      #       #../../backup-of-old-nixos/hosts/network/hostname.nix
      #       # ./backup-of-old-nixos/hosts/desktop/darkmode.nix

      #     ];
      #   };
      #   "deadbeef@l-x13s" = home-manager.lib.homeManagerConfiguration {
      #     pkgs = nixpkgs.legacyPackages.aarch64-linux; # Home-manager requires 'pkgs' instance
      #     extraSpecialArgs = { inherit inputs outputs; };
      #     modules = [
      #       # > Our main home-manager configuration file <
      #       # ./home-manager/home.nix
      #       ./home-manager/l-x13s/home.nix
      #       #../../backup-of-old-nixos/hosts/network/hostname.nix
      #       # ./backup-of-old-nixos/hosts/desktop/darkmode.nix

      #     ];
      #   };
      # };
    };
}
