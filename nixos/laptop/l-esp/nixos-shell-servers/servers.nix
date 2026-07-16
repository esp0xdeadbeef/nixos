{ lib
, pkgs
, self
, ...
}:

let
  mkVM = import "${self.outPath}/profiles/nixos/vm-host/nixos-shell/mk-vm.nix" {
    inherit pkgs lib self;
  };
in
{
  config = lib.mkMerge [
    (mkVM "s-test-l-esp" {
      autoStart = false;
      description = "l-esp test VM (nixos-shell)";
      nixBuildFlags = [ "--impure" ];
      persistDir = "/persist/vm-persists";
      repository = "path:${self.lib.vmSourceForHost "s-test-l-esp"}";
      restartTime = 30;
      stateDiskSize = "20G";
      workingDir = "/persist/nix-shell-vms";
    })
  ];
}
