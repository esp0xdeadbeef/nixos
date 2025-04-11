{
  description = "An optionally SecureBoot-enabled NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    # nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    impermanence.url = "github:nix-community/impermanence";

    sops-nix = {
      url = "github:Mic92/sops-nix";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-aarch64-widevine.url = "github:epetousis/nixos-aarch64-widevine";
    nixos-x13s.url = "github:BrainWart/x13s-nixos";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      lanzaboote,
      home-manager,
      nixos-x13s,
      nixos-aarch64-widevine,
      impermanence,
      sops-nix,
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
          sops-nix
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
                home-manager
                nixpkgs
                nixos-x13s
                nixos-aarch64-widevine
                ;
            }
            // import ./hosts/l-werk.nix { inherit mkNixOS nixpkgs-unstable; }
            // import ./hosts/l-esp.nix { inherit mkNixOS; }
            // import ./hosts/s-router-vpn-1.nix { inherit mkNixOS; }
            // import ./hosts/s-test-vm.nix {
              inherit
                mkNixOS
                nixpkgs
                nixpkgs-unstable
                home-manager
                sops-nix
                ;
            }
          );
    in
    {
      inherit nixosConfigurations;
    };
}
