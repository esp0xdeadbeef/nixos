{
  description = "esp0xdeadbeef nix config";

  inputs = {
    nixpkgs-stable = {
      url = "github:nixos/nixpkgs/nixos-26.05";
    };

    nixpkgs-unstable = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };

    nixpkgs = {
      # url = "github:nixos/nixpkgs/nixos-24.11";
      url = "github:nixos/nixpkgs/nixos-26.05";
      #url = "github:nixos/nixpkgs/nixos-unstable";
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

    network-renderer-nebula = {
      url = "github:esp0xdeadbeef/network-renderer-nebula";
    };

    network-compiler = {
      url = "github:esp0xdeadbeef/network-compiler";
    };

    network-forwarding-model = {
      url = "github:esp0xdeadbeef/network-forwarding-model";
    };

    network-control-plane-model = {
      url = "github:esp0xdeadbeef/network-control-plane-model";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    network-renderer-nixos = {
      url = "github:esp0xdeadbeef/network-renderer-nixos";
    };

    network-renderer-containerlab-linux-backend = {
      url = "github:esp0xdeadbeef/network-renderer-containerlab-linux-backend";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
    };

    network-labs = {
      url = "github:esp0xdeadbeef/network-labs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
    };

    khanelivim = {
      url = "github:khaneliman/khanelivim";
    };

    nvf = {
      url = "github:NotAShelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home manager
    #home-manager = {
    #  url = "github:nix-community/home-manager";
    #  inputs.nixpkgs.follows = "nixpkgs";
    #};

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
    hardware = {
      url = "github:nixos/nixos-hardware";
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware = {
      url = "github:nixos/nixos-hardware";
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    # X13s-only hardware module from:
    # https://github.com/NixOS/nixos-hardware/pull/1751
    #
    # This avoids dragging every other host onto the unmerged PR branch.
    nixos-hardware-x13s = {
      url = "github:BrainWart/nixos-hardware/x13s-updates";
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
    # nix run github:Mic92/nixos-shell -- --flake .#vm
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
      lib = nixpkgs.lib;
      inherit (self) outputs;

      systems = [
        "aarch64-linux"
        "i686-linux"
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      forAllSystems = lib.genAttrs systems;

      root = self.outPath;

      # Host architecture overrides.
      #
      # Most hosts are x86_64. The ThinkPad X13s is Qualcomm ARM64, so evaluating
      # it as x86_64-linux is wrong.
      hostSystems = {
        l-x13s = "aarch64-linux";
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
          abs = "${root}/${path}";
        in
        if builtins.pathExists abs then
          lib.filterAttrs (_: v: v == "directory") (builtins.readDir abs)
        else
          { };

      # Discover all hosts automatically
      hosts = lib.foldl' (
        acc: base: acc // lib.mapAttrs (name: _: "${base}/${name}") (listDirs base)
      ) { } hostRoots;

      allHostAbs = lib.mapAttrsToList (_: v: "${root}/${v}") hosts;

      # ------------------------------------------------------------
      # MINIMAL SOURCE PER HOST
      # ------------------------------------------------------------
      vmSourceForHost =
        name:
        let
          mine = "${root}/${hosts.${name}}";
          others = lib.filter (p: p != mine) allHostAbs;
        in
        builtins.path {
          name = "esp0xdeadbeef-vm-src-${name}";
          path = root;
          filter =
            p: _:
            let
              inOther = lib.any (o: lib.hasPrefix o p) others;
              inGit = lib.hasPrefix "${root}/.git" p;
            in
            # include everything EXCEPT other hosts and .git
            !(inOther || inGit);
        };
    in
    {
      lib = {
        inherit vmSourceForHost hosts;
      };

      packages =
        if builtins.pathExists ./pkgs then
          forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system})
        else
          { };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);

      overlays = if builtins.pathExists ./overlays then import ./overlays { inherit inputs; } else { };

      nixosModules = if builtins.pathExists ./modules/nixos then import ./modules/nixos else { };

      homeManagerModules =
        if builtins.pathExists ./modules/home-manager then import ./modules/home-manager else { };

      # ------------------------------------------------------------
      # GENERATED NIXOS CONFIGURATIONS
      # ------------------------------------------------------------
      nixosConfigurations = lib.mapAttrs (
        name: path:
        nixpkgs.lib.nixosSystem {
          system = hostSystemFor name;

          specialArgs = {
            inherit
              inputs
              outputs
              self
              name
              ;
            outPath = self.outPath;
          };

          modules = [
            (./. + "/${path}")
          ];
        }
      ) hosts;
    };
}
