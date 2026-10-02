{ lib, ... }:

# Pull in an optional machine-local override module.
#
# The repo is deployed to the board with `rsync --delete`, so a file inside
# this directory would be wiped on every deploy.  The board therefore keeps
# its overrides OUTSIDE the tree, at /etc/nixos.local.nix, and this module
# imports it when present.
#
# Used on-board to set `nixpkgs.buildPlatform = lib.mkForce "aarch64-linux"`:
# the flake defaults it to x86_64-linux so the SD card image can be
# cross-built on the laptop, but a rebuild running ON the board must build
# natively instead.
{
  imports = lib.optional (builtins.pathExists /etc/nixos.local.nix) /etc/nixos.local.nix;
}
