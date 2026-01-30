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
    (mkVM "s-infra" {
      description = "Infra VM (nixos-shell)";
      repository = "path:${self.lib.vmSourceForHost "s-infra"}";
    })

    (mkVM "s-nebula" {
      description = "Nebula VM (nixos-shell)";
      repository = "path:${self.lib.vmSourceForHost "s-nebula"}";
    })

    (mkVM "s-router-edge" {
      description = "s-router-edge VM (nixos-shell)";
      repository = "path:${self.lib.vmSourceForHost "s-router-edge"}";
    })

    (mkVM "s-router-core" {
      description = "s-router-core VM (nixos-shell)";
      repository = "path:${self.lib.vmSourceForHost "s-router-core"}";
    })
    (mkVM "s-gameserver" {
      description = "Gameserver VM (nixos-shell)";
      repository = "path:${self.lib.vmSourceForHost "s-gameserver"}";
    })

    (mkVM "s-router-vpn-egress" {
      description = "VPN-egress VM (nixos-shell)";
      repository = "path:${self.lib.vmSourceForHost "s-router-vpn-egress"}";
    })

    (mkVM "s-test" {
      description = "s-test (nixos-shell)";
      repository = "path:${self.lib.vmSourceForHost "s-test"}";
    })
  ];
}
