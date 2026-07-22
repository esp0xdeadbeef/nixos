{ config
, inputs
, lib
, ...
}:
let
  flakeInputs = lib.filterAttrs (inputName: input: inputName != "self" && lib.isType "flake" input) inputs;
in
{
  nix = {
    settings = {
      experimental-features = "nix-command flakes";
      flake-registry = "";
      nix-path = config.nix.nixPath;
    };

    channel.enable = false;
    registry = lib.mapAttrs (_: flake: { inherit flake; }) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
  };
}
