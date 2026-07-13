{ lib, outPath, ... }:

let
  keyFor = host: lib.fileContents "${outPath}/ssh-keys/deadbeef/${host}.pub";
in
{
  users.users.deadbeef.openssh.authorizedKeys.keys = [
    (keyFor "l-portal")
    (keyFor "l-esp")
    (keyFor "l-esp-root")
  ];

  sops.age.sshKeyPaths = [
    "/persist/etc/ssh/ssh_host_ed25519_key"
  ];

  services.openssh = {
    enable = true;

    hostKeys = [
      {
        type = "ed25519";
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
      }
    ];

    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    (keyFor "l-portal")
    (keyFor "l-esp")
    (keyFor "l-esp-root")
  ];

  programs.ssh.knownHosts.github-ed25519 = {
    hostNames = [ "github.com" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  };

  networking.firewall.allowedTCPPorts = [ 22 ];
  networking.firewall.checkReversePath = lib.mkForce false;
}
