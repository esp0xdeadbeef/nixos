{
  config,
  lib,
  ...
}:

let
  cfg = config.local.nix.cudaCache;

  containsNvidiaModule =
    modules:
    lib.any (
      module: module == "nvidia" || lib.hasPrefix "nvidia_" module || lib.hasPrefix "nvidia-" module
    ) modules;

  configuredKernelModules =
    (config.boot.kernelModules or [ ]) ++ (config.boot.initrd.kernelModules or [ ]);

  configuredExtraModulePackages = map (pkg: pkg.pname or pkg.name or "") (
    config.boot.extraModulePackages or [ ]
  );

  nvidiaDriverConfigured =
    lib.elem "nvidia" (config.services.xserver.videoDrivers or [ ])
    || containsNvidiaModule configuredKernelModules
    || lib.any (name: lib.hasInfix "nvidia" name) configuredExtraModulePackages;

  cacheEnabled = cfg.enable || (cfg.autoEnable && nvidiaDriverConfigured);

  enablePublicCudaCache = cacheEnabled && cfg.publicCudaCache.enable;
in
{
  options.local.nix.cudaCache = {
    enable = lib.mkEnableOption "CUDA binary cache configuration";

    autoEnable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Automatically enable CUDA binary caches when this NixOS configuration
        declares the Nvidia driver or Nvidia kernel modules.
      '';
    };

    publicCudaCache = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable the NixOS CUDA binary cache.";
      };

      url = lib.mkOption {
        type = lib.types.str;
        default = "https://cache.nixos-cuda.org";
        description = "URL for the public NixOS CUDA binary cache.";
      };

      publicKey = lib.mkOption {
        type = lib.types.str;
        default = "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=";
        description = "Trusted public key for the public NixOS CUDA binary cache.";
      };
    };
  };

  config = lib.mkIf enablePublicCudaCache {
    nix.settings = {
      extra-substituters = lib.mkAfter [ cfg.publicCudaCache.url ];
      extra-trusted-public-keys = lib.mkAfter [ cfg.publicCudaCache.publicKey ];
    };
  };
}
