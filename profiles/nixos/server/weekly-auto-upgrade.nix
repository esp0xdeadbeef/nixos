{ lib, ... }:

{
  # The shared autoupdate module (library/01-general/system/autoupdate.nix)
  # upgrades daily.  Hosts that also reboot on upgrade (operation = "switch",
  # allowReboot = true) can opt into a weekly cadence instead, so upgrades —
  # and the reboots they imply — are less disruptive.
  #
  # `dates` in the shared module is a plain assignment, so overriding it
  # requires mkForce (the same rule applies: use mkForce for this override).
  system.autoUpgrade.dates = lib.mkForce "Sun 04:30";
}
