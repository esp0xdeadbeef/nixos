# Neon-only intent shim for the testing model.
#
# `intent.nix` is the self-contained testing model (both sites), independent
# of prod-network/current. The CPM requires every runtime target in the
# supplied intent to be realized by the supplied inventory, so each router
# renderer compiles only its own site against its own context-specific
# inventory. This shim is a thin import-and-select surface, not a copy of the
# neon site definition.
{ esp0xdeadbeef.neon = (import ./intent.nix).esp0xdeadbeef.neon; }
