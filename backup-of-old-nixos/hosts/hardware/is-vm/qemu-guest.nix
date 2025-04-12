{ config, pkgs, ... }:
{
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;
  # VirtFS alternative for directory sharing
  services.spice-webdavd.enable = true;
}
