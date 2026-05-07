{
  publicIPv4Gateway = "172.31.1.1";
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC5cxs9N0nznf3pbzXsSnqp7YSjs3Xs0v/3ORCQLMf68 root@s-router-test"
  ];
  primaryInterface = "enp1s0";
  primaryInterfaceMac = "92:00:07:bc:57:e6";
  primaryInterfaceMatch = "en* eth*";
}
