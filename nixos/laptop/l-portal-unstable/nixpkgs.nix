# Run the X13s port on nixos-unstable, with board support from the PR #1751
# nixos-hardware branch. Same physical machine as l-portal, which stays on the
# release pin as the known-good rollback target.
#
# The value names a flake input (any input exposing `lib` and `legacyPackages`);
# `stable` means the flake's release-pinned `nixpkgs` and is the default.
{ nixpkgs = "nixpkgs-unstable"; }
