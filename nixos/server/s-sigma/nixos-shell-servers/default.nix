{
  pkgs,
  self,
  ...
}: {
  imports = [
    ./servers.nix
  ];

  local.vmHost.nixosShell.eno1RouterVms = {
    enable = true;
  };
}
