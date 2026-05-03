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
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII4DOWyfGq//5EEIELaWGzycaLWraxolll841gSKnHTo root@s-router-test"
  ];
  primaryInterface = "enp1s0";
  primaryInterfaceMac = "92:00:07:ae:79:ad";
  primaryInterfaceMatch = "en* eth*";
}
