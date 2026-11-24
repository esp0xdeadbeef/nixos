# Track nixos-unstable: s-tau is a builder host whose purpose is to follow
# current upstream, and its role does not depend on a specific release series.
#
# The value names a flake input (any input exposing `lib` and `legacyPackages`);
# `stable` means the flake's release-pinned `nixpkgs` and is the default.
{ nixpkgs = "nixpkgs-unstable"; }
