{ inputs }: final: _prev: {
  impermanenceNixosModule =
    args @ { config
    , lib
    , pkgs
    , ...
    }:
    let
      patchedLib =
        lib
        // {
          mkRemovedOptionModule = optionName: replacementInstructions:
            if optionName == [ "method" ]
            then _moduleArgs: { }
            else lib.mkRemovedOptionModule optionName replacementInstructions;
        };

      nixosUtils = import "${inputs.nixpkgs}/nixos/lib/utils.nix" {
        inherit config lib pkgs;
      };

      upstreamModule = inputs.impermanence.nixosModules.impermanence (
        args
        // {
          lib = patchedLib;
          utils = nixosUtils;
        }
      );
    in
    upstreamModule
    // {
      config = lib.mkMerge [
        (upstreamModule.config or { })
        {
          warnings = [
            "Using local impermanence module overlay: directory submodules currently trip the removed 'method' option on NixOS 26.05."
          ];
        }
      ];
    };
}
