{ config
, lib
, ...
}:

# Bridge between the host-local board switch (`local.bpiR4Pro.enable`, which the
# rest of this host -- network.nix, internet-guard.nix, fit.nix -- reads) and the
# nixos-hardware board module (`hardware.bananapi.bpi-r4-pro.enable`).
#
# In the real s-nodus this file OWNED the board config (kernel, DTB, console,
# bootloader).  Here that lives in inputs.nixos-hardware, so this file is only the
# option definition plus the one-line mapping.  Keeping the `local.bpiR4Pro`
# namespace means the copied host files (network.nix, cobalt-bridges.nix, ...)
# need no edits.
let
  cfg = config.local.bpiR4Pro;
in
{
  options.local.bpiR4Pro = {
    enable = lib.mkEnableOption "Banana Pi BPI-R4 Pro 4E board support";
  };

  config = lib.mkIf cfg.enable {
    hardware.bananapi.bpi-r4-pro.enable = true;
  };
}
