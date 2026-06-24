{ lib
, outPath
, ...
}:
let
  keyFor = host: lib.fileContents "${outPath}/ssh-keys/deadbeef/${host}.pub";
in
{
  users.users.deadbeef.openssh.authorizedKeys.keys = [
    (keyFor "l-portal")
    (keyFor "l-esp")
  ];
}
