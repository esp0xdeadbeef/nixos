{
  disko.devices = {
    disk = {
      vda = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02"; # for grub MBR
              priority = 1; # Needs to be first partition
            };
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "defaults"
                ];
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted";
                settings = {
                  allowDiscards = true;
                  keyFile = "/tmp/disk.key";
                };
                content = {
                  type = "btrfs";
                  extraArgs = ["-f"];
                  subvolumes = {
                    "/root" = {
                      mountpoint = "/";
                    };
                    # "/home/deadbeef" = {
                    #   mountOptions = ["compress=zstd"];
                    #   mountpoint = "/home/deadbeef";
                    # };
                    "/nix" = {
                      mountOptions = ["compress=zstd" "noatime"];
                      mountpoint = "/nix";
                    };
                    # "/games" = {
                    #   mountOptions = ["compress=zstd" "noatime"];
                    #   mountpoint = "/games";
                    # };
                    "/persist" = {
                      mountOptions = ["compress=zstd" "noatime"];
                      mountpoint = "/persist";
                    };
                    # "/swap" = {
                    #   mountpoint = "/.swapvol";
                    #   swap = {
                    #     swapfile.size = "20M";
                    #     swapfile2.size = "20M";
                    #     swapfile2.path = "rel-path";
                    #   };
                    # };
                  };
                  mountpoint = "/partition-root";
                };
              };
            };
          };
        };
      };
    };
  };
}