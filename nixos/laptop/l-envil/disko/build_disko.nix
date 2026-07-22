{ lib, relativeRepo, ... }:

let
  laptopHibernateSwapSize = import (relativeRepo.module "library/disko/laptop-hibernate-swap-size.nix");
in
{
  boot.initrd.luks.devices = {
    crypted = {
      keyFile = lib.mkForce null;
      crypttabExtraOpts = lib.mkAfter [
        "tpm2-device=auto"
        "tpm2-pcrs=7"
      ];
    };
    cryptswap = {
      keyFile = lib.mkForce null;
      crypttabExtraOpts = lib.mkAfter [
        "tpm2-device=auto"
        "tpm2-pcrs=7"
      ];
    };
  };

  disko.devices = {
    disk = {
      vda = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02"; # for grub MBR
              priority = 1; # Needs to be first partition
            };
            ESP = {
              size = "1G";
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
            swap = {
              size = laptopHibernateSwapSize { ramGiB = 64; };
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
                  resumeDevice = true;
                };
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
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    "/root" = {
                      mountpoint = "/";
                    };
                    # "/home/deadbeef" = {
                    #   mountOptions = ["compress=zstd"];
                    #   mountpoint = "/home/deadbeef";
                    # };
                    "/nix" = {
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                      mountpoint = "/nix";
                    };
                    # "/games" = {
                    #   mountOptions = ["compress=zstd" "noatime"];
                    #   mountpoint = "/games";
                    # };
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
