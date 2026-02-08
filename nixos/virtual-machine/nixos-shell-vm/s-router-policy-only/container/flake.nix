{
  description = "s-router-edge container (generated)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs =
    { self, nixpkgs, ... }:
    {
      nixosConfigurations.s-router-edge-container = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./default.nix ];
      };
    };
}
