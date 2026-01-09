{
  description = "NixOS libvirt qcow VM (working)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      packages.${system} = {
        vm = nixos-generators.nixosGenerate {
          inherit pkgs system;
          format = "qcow";     # ← THIS IS CORRECT
          modules = [ ./configuration.nix ];
        };

        default = self.packages.${system}.vm;
      };
    };
}

