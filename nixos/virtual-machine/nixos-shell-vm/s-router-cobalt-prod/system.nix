# The prod-shaped cobalt router; it also runs under KVM on s-nodus, so it must
# match the board. Without this it falls back to x86_64-linux, which builds an
# x86_64 runner wrapper around an aarch64 guest: the runner dies with
# `Exec format error` (exit 78/CONFIG) before the guest boots.
{ system = "aarch64-linux"; }
