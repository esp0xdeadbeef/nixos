{ lib, usesAlternateNixpkgs, ... }:
# Applied to every host; active only for hosts built from a non-primary nixpkgs.
#
# When `nixpkgs.flake.setFlakeRegistry` is on (the default for flake-built
# systems), nixpkgs hard-codes `nix.registry.nixpkgs` to `config.nixpkgs.pkgs.path`
# and *also* derives it from the flake's own `nixpkgs` input. On a host built
# from a different tree those two definitions disagree and evaluation aborts:
#
#   error: The option `nix.registry.nixpkgs.to.path' has conflicting definition values
#
# Such a host is not the machine's registry source for `nixpkgs` -- the flake
# pins that explicitly -- so the derived entry and `nix-path` are dropped. This
# follows from the tree choice rather than being a per-host decision, which is
# why it lives here instead of being repeated in every unstable host.
{
  config = lib.mkIf usesAlternateNixpkgs {
    nixpkgs.flake.setFlakeRegistry = lib.mkForce false;
    nixpkgs.flake.setNixPath = lib.mkForce false;
  };
}
