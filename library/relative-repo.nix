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
  #
  # This is for DERIVATION inputs (sops files, key files read by lib.fileContents
  # at build time): it keeps the evaluated tree small by copying only the named
  # paths into the store.  Its result is a store-path STRING, so it must not be
  # read at evaluation time -- see `sourceModule`.
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

  # Eval-time read of a repository path (import, readFile, readDir).
  #
  # `source`/`sourcePath` return a store-path STRING produced by
  # `lib.fileset.toSource`.  Interpolating that string into a longer path and
  # then reading it works under `nix eval` but NOT under pure evaluation
  # (`nix flake check`): the string's store context is lost, so Nix tries to
  # read a bare `<hash>-source` with no `/nix/store` prefix and fails with
  # "path ... is not valid".  It also would force `lib.fileset.toSource` to
  # realise a store path during evaluation.
  #
  # `root` is already the flake source, so joining a sub-path onto it costs no
  # extra copy and keeps the path real (context-preserving).  That is exactly
  # what `module` does for imports; `sourceModule` names the same thing for the
  # intent/inventory/readDir case so the distinction is explicit at call sites:
  #
  #   derivation input (sops, keys) -> sourcePath
  #   evaluated at eval time       -> sourceModule
  sourceModule = module;
}
