{
  publicIPv4 = "62.238.15.116";
  publicIPv4Gateway = "172.31.1.1";
  publicIPv6 = "2a01:4f9:c012:7695::/64";
  publicIPv6Address = "2a01:4f9:c012:7695::1/64";
  floatingIPv6Prefixes = [
    "2a01:4f9:c01f:18::/64"
  ];
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK3PqfP7w7JtqZ7UoJblIc66gt8/GWHNtGPiWgmtLk8u root@s-router-test"
  ];
  primaryInterface = "eth0";
  primaryInterfaceMac = "92:00:07:ae:94:36";
  primaryInterfaceMatch = "en* eth*";
}
