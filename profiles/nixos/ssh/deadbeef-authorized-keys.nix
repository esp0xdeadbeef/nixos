{ lib
, relativeRepo
, ...
}:
let
  keyFor = host: lib.fileContents (relativeRepo.sourcePath "ssh-keys/deadbeef/${host}.pub");
in
{
  users.users.deadbeef.openssh.authorizedKeys.keys = [
    (keyFor "l-portal")
    (keyFor "l-esp")
    (keyFor "s-sigma")
    (keyFor "s-sigma-root")
  ];
}
