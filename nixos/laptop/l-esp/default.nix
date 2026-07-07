{ inputs
, lib
, profiles
, ...
}:
{
  imports = [
    profiles.nixos.laptop.intel-workstation
    profiles.nixos.vm-host.nixos-shell

    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p16s-intel-gen2

    ./connect-nas
    ./hardware
    ./llms
    ./nebula-node
    ./optional
    ./nixos-shell-servers
  ];

  hardware.nvidia.prime = {
    intelBusId = "PCI:00:02:0";
    nvidiaBusId = "PCI:01:00:0";
  };

  services.autorandr.enable = lib.mkForce false;
  local.laptop.autorandrDefault.enable = false;

  local.laptop.monitorLayouts.samsungLu28r55Desk = {
    enable = true;
    left = "samsung:lu28r55:f23519db73329d63";
    right = "samsung:lu28r55:f238aadb7335c99d";
    targetResolution = "3840x2160";
    internalScale = "1x1";
  };

  environment.etc.hosts.enable = false;

  systemd.tmpfiles.rules = [
    "d /home/deadbeef/.quickget/windows-10 0755 deadbeef users -"
    "h /home/deadbeef/.quickget/windows-10 - - - - +C"
    "d /home/deadbeef/.quickget/windows-11 0755 deadbeef users -"
    "h /home/deadbeef/.quickget/windows-11 - - - - +C"
  ];

  system.stateVersion = "24.11";
}
