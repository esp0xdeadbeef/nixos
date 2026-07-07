{ pkgs, profiles, ... }:
{
  imports = [
    profiles.nixos.server.dell-vm-host
    profiles.nixos.llm-clients.agents

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

  # Keep the same VM declarations as s-sigma, but do not start them on tau
  # until the active/standby router plan is explicit.
  local.vmHost.nixosShell.autoStart = false;

  system.stateVersion = "25.11";
}
