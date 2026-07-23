{ pkgs, profiles, ... }:
{
  imports = [
    profiles.nixos.server.dell-vm-host
    profiles.nixos.server.no-sleep
    profiles.nixos.llm-clients.agents
    profiles.nixos.virtualization.pci-passthrough

    ./libvirt.nix
    ./nixos-shell-servers
    ./hardware
    ./connect-nas
  ];

  boot.swraid = {
    # Disko creates the LUKS container on this mdraid array; the initrd must
    # assemble it before cryptsetup can find the root device UUID.
    enable = true;
    mdadmConf = ''
      ARRAY /dev/md/root metadata=1.2 UUID=82520a72:9a366735:99afae75:870b517f
      PROGRAM ${pkgs.coreutils}/bin/true
    '';
  };

  local.virtualization.pciPassthrough = {
    enable = true;
    devices.tesla-p100 = {
      pciAddress = "0000:03:00.0";
      vmName = "s-llm-inference";
    };
  };

  system.stateVersion = "25.11";
}
