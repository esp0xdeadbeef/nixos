{ lib, root }:

let
  clean = rel: lib.removePrefix "/" rel;
  resolve = rel: root + "/${clean rel}";
in
rec {
  # Eval-only module paths retain their surrounding source tree, so relative
  # imports inside the selected module keep working.
  module = resolve;

  exists = rel: builtins.pathExists (resolve rel);

  # Select only explicit runtime/derivation inputs while preserving their paths
  # relative to the repository root.
  source = relativePaths:
    lib.fileset.toSource {
      inherit root;
      fileset = lib.fileset.unions (map resolve relativePaths);
    };

  sourcePath = rel:
    source [ rel ] + "/${clean rel}";

  # Use for lower-priority module defaults that may be replaced by a
  # host-specific file before the option is consumed.
  sourcePathMaybeMissing = rel:
    lib.fileset.toSource
      {
        inherit root;
        fileset = lib.fileset.maybeMissing (resolve rel);
      }
    + "/${clean rel}";
}
