{
  publicIPv4Gateway = "172.31.1.1";
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJgP9poriB7swAA5XZ3bUIKPyj8Ho6Diun2AiwTemGrr root@s-router-test"
  ];
  primaryInterface = "eth0";
  primaryInterfaceMac = "92:00:07:c4:0d:3c";
  primaryInterfaceMatch = "en* eth*";
}
