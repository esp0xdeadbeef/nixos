{ lib
, relativeRepo
, ...
}:
{
  sops.defaultSopsFile = lib.mkForce (relativeRepo.sourcePath "secrets/s-router-policy-only.yaml");

  sops.secrets.subnet-ipv6 = {
    owner = "root";
    mode = "0400";
    sopsFile = relativeRepo.sourcePath "secrets/s-router-policy-only.yaml";
  };
}
