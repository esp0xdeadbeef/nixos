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
    (mkVM "s-router-legacy-edge" {
      description = "s-router-legacy-edge VM (nixos-shell)";
      repository = "path:${self.lib.vmSourceForHost "s-router-legacy-edge"}";
    })
    (mkVM "s-router-legacy-core" {
      description = "s-router-core VM (nixos-shell)";
      repository = "path:${self.lib.vmSourceForHost "s-router-legacy-core"}";
    })
    (mkVM "s-router-core" {
      description = "s-router-core VM (nixos-shell)";
      repository = "path:${self.lib.vmSourceForHost "s-router-core"}";
    })
    (mkVM "s-router-upstream-selector" {
      description = "s-router-upstream-selector VM (nixos-shell)";
      repository = "path:${self.lib.vmSourceForHost "s-router-upstream-selector"}";
    })

    (mkVM "s-router-policy-only" {
      description = "s-router-policy-only VM (nixos-shell)";
      repository = "path:${self.lib.vmSourceForHost "s-router-policy-only"}";
    })

    (mkVM "s-router-access" {
      description = "s-router-access VM (nixos-shell)";
      repository = "path:${self.lib.vmSourceForHost "s-router-access"}";
    })
    (mkVM "s-router-test" {
      description = "s-router-test VM (nixos-shell)";
      repository = "path:${self.lib.vmSourceForHost "s-router-test"}";
    })
    (mkVM "s-router-vpn-egress" {
      description = "VPN-egress VM (nixos-shell)";
      repository = "path:${self.lib.vmSourceForHost "s-router-vpn-egress"}";
    })

    (mkVM "s-gameserver" {
      description = "Gameserver VM (nixos-shell)";
      repository = "path:${self.lib.vmSourceForHost "s-gameserver"}";
    })

    (mkVM "s-test" {
      description = "s-test (nixos-shell)";
      repository = "path:${self.lib.vmSourceForHost "s-test"}";
    })
  ];
}
