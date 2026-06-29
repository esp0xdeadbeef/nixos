{
  disko.devices = {
    disk = {
      boot = {
        # Use non-serial by-path names so this public repo does not expose disk
        # serials while still avoiding probe-order names like /dev/sda.
        device = "/dev/disk/by-path/pci-0000:00:1a.0-usb-0:1.3:1.0-scsi-0:0:0:0";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "2G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
          };
        };
      };

      root-a = {
        device = "/dev/disk/by-path/pci-0000:82:00.0-nvme-1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            mdadm = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "root";
              };
            };
          };
        };
      };

      root-b = {
        device = "/dev/disk/by-path/pci-0000:83:00.0-nvme-1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            mdadm = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "root";
              };
            };
          };
        };
      };
    };

    mdadm = {
      root = {
        type = "mdadm";
        level = 0;
        content = {
          type = "luks";
          name = "crypted";
          passwordFile = "/tmp/s-tau-luks.key";
          settings.allowDiscards = true;
          content = {
            type = "btrfs";
            subvolumes = {
              "/root" = {
                mountpoint = "/";
              };
              "/nix" = {
                mountpoint = "/nix";
              };
              "/persist" = {
                mountpoint = "/persist";
              };
              "/vmstore" = {
                mountpoint = "/vmstore";
                mountOptions = [
                  "nodatacow"
                  "noatime"
                ];
              };
            };
          };
        };
      };
    };
  };
}
