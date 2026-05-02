{
  publicIPv4 = "62.238.15.116";
  publicIPv6 = "2a01:4f9:c014:c422::/64";
  publicIPv6Address = "2a01:4f9:c014:c422::1/64";
  floatingIPv6Prefixes = [
    "2a01:4f9:c01f:77::/64"
  ];
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFWMx/YX1Ej+85946ek5/UfZVRJ+Ufi7rr+tS/XHpQvN root@s-router-test"
  ];
  primaryInterface = "ens3";
  primaryInterfaceMatch = "en* eth0";
}
