{ outputs, ... }:
{
  # Everything here runs unconditionally on every host that imports
  # home-manager/l-esp/home.nix. Anything machine-specific must gate itself on
  # `systemHostName`: this tree is also the source for router guests (see
  # profiles/nixos/nixos-shell-host/common.nix), where host-specific units
  # would start and fail forever.
  imports = outputs.lib.enabledImportsRecursive ./.;
}
