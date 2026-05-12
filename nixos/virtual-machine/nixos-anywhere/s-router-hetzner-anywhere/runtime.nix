{
  publicIPv4Gateway = "172.31.1.1";
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOf+nCvCD1R6BiF2grYoh2mZCWTFnvwmsvDvpMzE8T51 root@s-router-test"
  ];
  primaryInterface = "eth0";
  primaryInterfaceMac = "92:00:07:c7:9c:21";
  primaryInterfaceMatch = "en* eth*";
}
