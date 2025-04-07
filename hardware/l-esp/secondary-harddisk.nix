{ config, pkgs, ... }:
{

  #  fileSystems."/home/deadbeef/second-ssd" = {
  #    device = "/dev/mapper/data_disk";
  #    fsType = "ext4";  # Change if using another filesystem
  #    neededForBoot = false;  # Ensures this is not blocking boot
  #  };
  environment.etc.crypttab = {
    mode = "0600";
    text = ''
      # <volume-name> <encrypted-device> [key-file] [options]
      second_ssd UUID=f08f365d-f678-4f26-9ef4-c379db36d470 /root/.keyfiles/key_luks luks
    '';
  };

  # Veracrypt mount
  fileSystems."/home/deadbeef/second-ssd" = {
    device = "/dev/mapper/second_ssd";
    # For customising filesystem type
    # fsType = "ntfs-3g";
    # options = [ "defaults,rw,dmask=027,fmask=037,uid=1000,guid=1000,windows_names,permissions,nofail 0 0" ];
  };

}
