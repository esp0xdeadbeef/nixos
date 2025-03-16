            { config, pkgs, ... }: {
              #############################
              # Bootloader and Kernel Options
              #############################
boot.loader.systemd-boot.configurationLimit = 15;
#boot.loader.systemd-boot.enable = false;
boot.loader.efi.canTouchEfiVariables = true;
environment.systemPackages = with pkgs; [
  tpm2-tss
  sbctl
];
boot.initrd.systemd.enable = true;

fileSystems."/".options = [ "noatime" ];
#swapDevices = [ ]; 

}
