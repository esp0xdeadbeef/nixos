{
  disko.devices = {
    disk = {
      boot = {
        # The NixOS installer USB is /dev/sda on this box. Use by-id so Disko
        # targets the internal Dell IDSDM boot device regardless of probe order.
        device = "/dev/disk/by-id/usb-DELL_IDSDM_012345678901-0:0";
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
        device = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S69ENF0W826691E";
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
        device = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S69ENF0W826718V";
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
