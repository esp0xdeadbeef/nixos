# Explicit overwrite: keep legcord on unstable until the stable package set
# carries the same fixed dependency graph.
final: _prev: {
  legcord =
    builtins.trace
      "WARNING: local legcord overlay is active: pkgs.legcord = pkgs.unstable.legcord."
      final.unstable.legcord;
}
