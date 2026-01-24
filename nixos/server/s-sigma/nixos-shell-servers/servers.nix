{
  lib,
  pkgs,
  self,
  ...
}:
# for testing, use:
# nix run path:/home/deadbeef/github/nixos#nixosConfigurations.<vm-hostname>.config.system.build.nixos-shell
# or:
# export HOST="<vm-hostname>" ; nixos-rebuild switch --impure --flake path:/home/deadbeef/github/nixos#$(hostname) && grep build $(systemctl cat $HOST-image.service | grep Exec | cut -d '=' -f 2) | bash && systemctl restart -- $(ls /etc/systemd/system/s-*-image.service 2>/dev/null | xargs -n1 basename)

let
  mkVM = import ./mk-nixos-shell-vm.nix { inherit pkgs lib self; };
in
{
  config = lib.mkMerge [
    (mkVM "s-infra" (
      let
        repo = self.lib.vmSourceForPath "nixos/virtual-machine/nixos-shell-vms/s-infra";
      in
      {
        description = "Infra VM (nixos-shell)";
        repository = "path:${repo}";
      }
    ))

    (mkVM "s-router-edge" (
      let
        repo = self.lib.vmSourceForPath "nixos/virtual-machine/nixos-shell-vms/s-router-edge";
      in
      {
        description = "s-router-edge VM (nixos-shell)";
        repository = "path:${repo}";
      }
    ))

    (mkVM "s-gameserver" (
      let
        repo = self.lib.vmSourceForPath "nixos/virtual-machine/nixos-shell-vms/s-gameserver";
      in
      {
        description = "Gameserver VM (nixos-shell)";
        repository = "path:${repo}";
      }
    ))

    (mkVM "s-router-vpn-egress" (
      let
        repo = self.lib.vmSourceForPath "nixos/virtual-machine/nixos-shell-vms/s-router-vpn-egress";
      in
      {
        description = "VPN-egress VM (nixos-shell)";
        repository = "path:${repo}";
      }
    ))

    (mkVM "s-test" (
      let
        repo = self.lib.vmSourceForPath "nixos/virtual-machine/nixos-shell-vms/s-test";
      in
      {
        description = "s-test (nixos-shell)";
        repository = "path:${repo}";
        ephemeralRoot = true;
      }
    ))
  ];
}
