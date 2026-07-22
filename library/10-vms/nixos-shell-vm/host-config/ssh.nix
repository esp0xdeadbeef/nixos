{ lib
, relativeRepo
, ...
}:
let
  keyFor = host: lib.fileContents (relativeRepo.sourcePath "ssh-keys/deadbeef/${host}.pub");
in
{
  services.openssh = {
    enable = true;
    hostKeys = [
      {
        type = "ed25519";
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
      }
      {
        type = "rsa";
        bits = 4096;
        path = "/persist/etc/ssh/ssh_host_rsa_key";
      }
    ];
  };
  users.users.root.openssh.authorizedKeys.keys = [
    (keyFor "codex-jail")
  ];
  users.users.deadbeef.openssh.authorizedKeys.keys = [
    (keyFor "codex-jail")
  ];
}
