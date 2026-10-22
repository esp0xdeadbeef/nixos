_final: prev: {
  # mdbook 0.5.2 in the current nixpkgs pin fails its own testsuite:
  #
  #   renderer::missing_renderer
  #   renderer::missing_optional_not_fatal
  #   ... (5 failures / 104 passed)
  #
  # The package builds and runs correctly -- only `--test testsuite` is
  # broken, and the resulting path is NOT substitutable from
  # cache.nixos.org, so every host that has to build `nix` locally fails in
  # `nix-manual` -> `nix` -> `nixos-rebuild-ng`.
  #
  # Nothing in this repo consumes mdbook at runtime; it is only the
  # renderer for the Nix manual.  Skipping the check is therefore safe and
  # strictly a build-time workaround.  Remove this overlay once the nixpkgs
  # pin ships an mdbook whose testsuite passes.
  mdbook = prev.mdbook.overrideAttrs (_: {
    doCheck = false;
  });
}
