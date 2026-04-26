{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/vda";

      content = {
        type = "gpt";

        partitions = {
          boot = {
            size = "1M";
            type = "EF02";
          };

          root = {
            size = "100%";

            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];

              subvolumes = {
                "/boot" = {
                  mountpoint = "/boot";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };

                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };

                "/persist" = {
                  mountpoint = "/persist";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
              };
            };
          };
        };
      };
    };
  };

  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    options = [
      "defaults"
      "size=8G"
      "mode=755"
    ];
  };
}
