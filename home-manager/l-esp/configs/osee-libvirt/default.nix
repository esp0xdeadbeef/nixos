{ config, pkgs, ... }:
{
  # Get these flags by using:
  # dconf watch /
  #/org/virt-manager/virt-manager/vms/d242307c3aba4cc8931f829dea768f63/resize-guest
  dconf.settings = {
    "org/virt-manager/virt-manager/vms/d242307c3aba4cc8931f829dea768f63" = {
      "resize-guest" = 1;
    };
  };
}
