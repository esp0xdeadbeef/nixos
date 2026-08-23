# Neon-only intent shim.
#
# `intent.nix` models both sites in one file (single baseline source of truth).
# The CPM requires every runtime target in the supplied intent to be realized
# by the supplied inventory, so each router renderer compiles only its own
# site against its own context-specific inventory. This shim is a thin
# import-and-select surface, not a copy of the neon site definition.
{ esp0xdeadbeef.neon = (import ./intent.nix).esp0xdeadbeef.neon; }
