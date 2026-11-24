{ ... }:

{
  boot.loader.efi.canTouchEfiVariables = true;

  # No `boot.initrd.systemd.enable` here: the scripted initrd was removed in
  # nixos-unstable (26.11), where the systemd initrd is the only implementation
  # and setting the option is a hard evaluation error. This host tracks
  # nixos-unstable (see ../../nixpkgs.nix), so the option must not be set.
}
