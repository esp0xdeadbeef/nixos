{
  lib,
  outPath,
  ...
}:
{
  sops.defaultSopsFile = lib.mkForce "${outPath}/secrets/s-router-policy-only.yaml";

  sops.secrets.subnet-ipv6 = {
    owner = "root";
    mode = "0400";
    sopsFile = "${outPath}/secrets/s-router-policy-only.yaml";
  };
}
