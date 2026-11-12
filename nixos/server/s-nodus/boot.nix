{ config
, lib
, ...
}:

# Bridge between the host-local board switch (`local.bpiR4Pro.enable`, which the
# rest of this host -- network.nix, internet-guard.nix -- reads) and the
# nixos-hardware board module (`hardware.bananapi.bpi-r4-pro.enable`).
#
# This file used to OWN the board config: kernel, DTB, console, bootargs, the
# "no NixOS bootloader" policy, and the raw-FIT boot chain.  All of that now
# lives in inputs.nixos-hardware's bananapi/bpi-r4-pro, including the boot chain
# (BL2 + FIP + U-Boot with CONFIG_EFI_LOADER -> systemd-boot on an ESP).
#
# Keeping the `local.bpiR4Pro` namespace is deliberate: the rest of this host
# (network.nix, cobalt-bridges.nix, ...) reads it, so a rename would be churn
# without meaning.
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
