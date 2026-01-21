{
  lib,
  pkgs,
  self,
  ...
}:

let
  mkVM = import ./mk-nixos-shell-vm.nix { inherit pkgs lib self; };

  useLocalRepo = true;

  repoArg = if useLocalRepo then "path:/home/deadbeef/github/nixos" else null;

  withRepo =
    attrs:
    if repoArg == null then
      builtins.removeAttrs attrs [ "repository" ]
    else
      attrs // { repository = repoArg; };

in
{
  config = lib.mkMerge [
    (mkVM "s-infra" (withRepo {
      description = "Infra VM (nixos-shell)";
      extraTmpfiles = [
        "d /persist/infra/unifi 0755 root root -"
      ];
    }))

    (mkVM "s-router-edge" (withRepo {
      description = "s-router-edge VM (nixos-shell)";
    }))

    (mkVM "s-gameservers" (withRepo {
      description = "Gameserver VM (nixos-shell)";
      restartTime = 1;
    }))

    (mkVM "s-router-vpn-egress" (withRepo {
      description = "VPN-egress VM (nixos-shell)";
    }))

    (mkVM "s-test" (withRepo {
      description = "s-test (nixos-shell)";
      ephemeralRoot = true;
      #buildDelaySec = 60;
    }))
  ];
}
