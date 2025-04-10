{
  description = "An optionally SecureBoot-enabled NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    # nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nixos-x13s.url = "github:BrainWart/x13s-nixos";
    impermanence.url = "github:nix-community/impermanence";
    nixos-aarch64-widevine.url = "github:epetousis/nixos-aarch64-widevine";
  };

  outputs =
    {
      self,
      nixpkgs,
      lanzaboote,
      home-manager,
      nixos-x13s,
      nixos-aarch64-widevine,
      impermanence,
      ...
    }:
    let
      lib = nixpkgs.lib;

      mkNixOS = import ./lib/mkNixOS.nix {
        inherit
          lib
          lanzaboote
          impermanence
          home-manager
          nixpkgs
          nixpkgs-unstable
          ;
      };
      nixosConfigurations =
        lib.foldlAttrs
          (
            acc: name: value:
            acc // { ${name} = value; }
          )
          { }
          (
            import ./hosts/l-x13s.nix {
              inherit
                mkNixOS
                nixos-x13s
                nixos-aarch64-widevine
                home-manager
                nixpkgs
                ;
            }
            // import ./hosts/l-werk.nix { inherit mkNixOS; }
            // import ./hosts/l-esp.nix { inherit mkNixOS; }
            // import ./hosts/s-router-vpn-1.nix { inherit mkNixOS; }
            // import ./hosts/s-test-vm.nix { inherit mkNixOS; }
          );

    in
    {
      inherit nixosConfigurations;
    };
}
