{
  publicIPv4Gateway = "172.31.1.1";
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA1Rmk/3OrwWB5qvWrltIDGgK2vxQIXfRtPkAg56gHB1 deadbeef@l-x13s"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGbC/c5eOjweQYu4KHyKUG14zsRaXebePCRGeNWUkYly root@s-router-test"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIj7Kz9Fo3D1ZSjuA7lNJg+ERfAoZ2howWvHejtHT8sK root@s-router-test"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIErXiiIRhEdCcHiLPj9yIwYzytMBzHdWA81oRGpATNOS root@s-router-test"
  ];
  primaryInterface = "enp1s0";
  primaryInterfaceMac = "92:00:07:d4:70:af";
  primaryInterfaceMatch = "en* eth*";
}
