{ pkgs
, self
, ...
}: {
  imports = [
    ./servers.nix
  ];

  services.nixosShellVmManager.carrierControls.eno1-router-vms = {
    interface = "eno1";
    requiredInterfaces = [
      "vmbr1"
      "vmbr4"
    ];
    instances = [ "s-router-prod" ];
    description = "Start or stop router nixos-shell VMs from eno1 carrier";
  };
}
