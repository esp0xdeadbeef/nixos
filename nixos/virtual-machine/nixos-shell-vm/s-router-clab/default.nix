{
  outPath,
  lib,
  config,
  ...
}:
let
  vmRoot =
    let
      file = __curPos.file;
    in
    builtins.dirOf file;
in
{
  _module.args.vmRoot = vmRoot;

  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config"
    ./overwrites.nix
    ./container-settings.nix
    ./host-deploy.nix
  ];
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
  ];
  users.users.deadbeef.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
  ];

}
