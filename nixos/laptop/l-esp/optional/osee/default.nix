{ profiles, ... }:
{
  imports = [
    profiles.nixos.workstation.binary-exploitation
    ./lxc-osee/bind-to-lxc.nix
    ./lxc-osee/x2go-client.nix
  ];
}
