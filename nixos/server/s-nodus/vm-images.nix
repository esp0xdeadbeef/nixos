# The images s-nodus boots, keyed by VM name.
#
# `vmImageBuilds` (passed in from flake.nix) maps every nixos-shell VM in this
# flake to its build. That is the *derived* image, which changes whenever any
# input changes -- including a transitive nixpkgs bump nobody considers
# production.
#
# IMPORTANT: for the production router that is not acceptable. On 2026-11-07
# such a bump moved the prod image's store path (7mdq7c7f -> 3ja6ivx0), the
# manager booted the new one, the guest never brought QGA up, and the site lost
# its router while every `*-prod` flake pin was provably unchanged.
#
# So the production image is PINNED BY CONTENT: the known-good store path is
# copied into a derivation, which makes its output path independent of input
# bumps. Changing the production image therefore requires editing the literal
# below -- a deliberate act, not a side effect of `nix flake update`.
#
# `builtins.pathExists` keeps evaluating on machines that do not hold the image
# (they get the derived build), so only the machine that runs prod is pinned.
{ lib, pkgs, derived }:

let
  prodImage = "/nix/store/7mdq7c7f6l9i651v8idi2lxl886js87j-nixos-vm";
in
{
  s-router-cobalt-new = derived.s-router-cobalt-new;

  # Prod cobalt router is the carrier-managed instance (see ./vm-host.nix);
  # s-router-cobalt-new is kept only as the rollback target, so its image must
  # stay buildable.
  s-router-cobalt-prod =
    if builtins.pathExists prodImage then
      pkgs.runCommandLocal "s-router-cobalt-prod-pinned-nixos-vm"
        { preferredLocalBuilders = [ "@none" ]; }
        "cp -L ${builtins.storePath prodImage} $out"
    else
      derived.s-router-cobalt-prod;
}
