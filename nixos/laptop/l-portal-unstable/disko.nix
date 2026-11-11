let
  swapSize = "24G";
in
{
  disko.devices = {
    disk = {
      nvme0n1 = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1075M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                extraArgs = [
                  "-n"
                  "NIXBOOT"
                ];
                mountpoint = "/boot";
                mountOptions = [
                  "fmask=0022"
                  "dmask=0022"
                ];
              };
            };
            swap = {
              size = swapSize;
              content = {
                type = "luks";
                name = "cryptswap";
                settings = {
                  allowDiscards = true;
                  keyFile = "/tmp/disk.key";
                };
                content = {
                  type = "swap";
                  discardPolicy = "both";
                  resumeDevice = false;
                };
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "root";
                settings = {
                  allowDiscards = true;
                  keyFile = "/tmp/disk.key";
                };
                content = {
                  type = "btrfs";
                  extraArgs = [
                    "-f"
                    "-L"
                    "nixos-root"
                  ];
                  subvolumes = {
                    "/root" = {
                      mountpoint = "/";
                    };
                    "/nix" = {
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                      mountpoint = "/nix";
                    };
                    "/persist" = {
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                      mountpoint = "/persist";
                    };
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
