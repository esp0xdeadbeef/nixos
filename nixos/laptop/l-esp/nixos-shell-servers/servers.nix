{
  lib,
  pkgs,
  self,
  ...
}:

let
  mkVM = import "${self.outPath}/profiles/nixos/vm-host/nixos-shell/mk-vm.nix" {
    inherit pkgs lib self;
  };
in
{
  config = lib.mkMerge [
    (mkVM "s-test-l-esp" {
      description = "l-esp test VM (nixos-shell)";
      repository = "path:/home/deadbeef/github/nixos";
      workingDir = "/persist/nix-shell-vms";
      persistDir = "/persist/vm-persists";
      restartTime = 30;
      stateDiskSize = "20G";
      autoStart = false;
      nixBuildFlags = [ "--impure" ];
    })
  ];
}
