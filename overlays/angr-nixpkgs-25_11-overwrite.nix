# Explicit overwrite: angr 9.2.193 in nixpkgs-unstable (and stable 26.05) fails
# to build because its setup.py requires setuptools-rust while setuptools-rust
# is missing from build-system. Pin to the 25.11 package set (9.2.154) until
# the packaging is fixed upstream.
final: _prev: {
  angr =
    builtins.trace
      "WARNING: local angr overlay is active: pkgs.angr = pkgs.nixpkgs-25_11.python3Packages.angr."
      final.nixpkgs-25_11.python3Packages.angr;
}
