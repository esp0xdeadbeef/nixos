{ outPath
, lib
, ...
}:

{
  _module.args.sRouterClabLabProfile = {
    labSource = "sat";
    deploymentHost = "s-router-clab";
  };
  networking.hostName = lib.mkForce "s-router-clab";

  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config"
    ./management-vlan2.nix
  ];
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
  ];
  users.users.deadbeef.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
  ];
}
