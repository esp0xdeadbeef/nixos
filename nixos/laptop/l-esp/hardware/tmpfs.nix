{ ... }:

{
  fileSystems."/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
  };
}
