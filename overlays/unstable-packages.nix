{ inputs }: final: prev:
let
  ollamaSplitGGUF = _unstableFinal: unstablePrev:
    let
      cudaPackages = unstablePrev.cudaPackages;
      cudaLibs = [
        cudaPackages.cuda_cudart
        cudaPackages.libcublas
        cudaPackages.cccl
      ];
      cudaMajorVersion = final.lib.versions.major cudaPackages.cuda_cudart.version;
      ollamaCudaToolkit = unstablePrev.buildEnv {
        name = "cuda-merged-${cudaMajorVersion}";
        paths =
          map final.lib.getLib cudaLibs
          ++ [
            (final.lib.getOutput "static" cudaPackages.cuda_cudart)
            (final.lib.getBin (cudaPackages.cuda_nvcc.__spliced.buildHost or cudaPackages.cuda_nvcc))
          ];
        ignoreCollisions = true;
      };
      patchOllama =
        { package
        , cuda ? false
        ,
        }:
        package.overrideAttrs (
          old:
          { }
          // final.lib.optionalAttrs cuda {
            # setupCudaHook exposes the splayed CUDA outputs as a
            # semicolon-separated CUDAToolkit_ROOT. Ollama 0.32.4 passes
            # that value into a nested CMake ExternalProject, whose
            # FindCUDAToolkit treats it as one malformed path. Reset it
            # after the configure hooks to the equivalent merged toolkit.
            preBuild = ''
              export CUDAToolkit_ROOT=${ollamaCudaToolkit}
              export CUDAToolkit_INCLUDE_DIR="$CUDAToolkit_ROOT/include"
            ''
            + (old.preBuild or "");
          }
        );
    in
    {
      ollama = patchOllama { package = unstablePrev.ollama; };
      ollama-cpu = patchOllama { package = unstablePrev.ollama-cpu; };
      ollama-cuda = patchOllama {
        package = unstablePrev.ollama-cuda;
        cuda = true;
      };
      ollama-rocm = patchOllama { package = unstablePrev.ollama-rocm; };
      ollama-vulkan = patchOllama { package = unstablePrev.ollama-vulkan; };
    };

  pynfsclientMetadataVersion = _unstableFinal: unstablePrev: {
    pythonPackagesExtensions =
      (unstablePrev.pythonPackagesExtensions or [ ])
      ++ [
        (
          _pythonFinal: pythonPrev:
            let
            in
            {
              bloodhound-py =
                let
                  expectedVersion = "1.9.0";
                  actualVersion =
                    pythonPrev.bloodhound-py.version
                      or (final.lib.getVersion pythonPrev.bloodhound-py.name);
                in
                assert final.lib.assertMsg (actualVersion == expectedVersion)
                  "bloodhound-py overlay expects ${expectedVersion}, got ${actualVersion}; remove the distribution-name fix once nixpkgs uses the upstream name.";
                builtins.trace
                  "WARNING: local bloodhound-py distribution-name workaround is active; remove it once nixpkgs uses pname bloodhound."
                  (
                    pythonPrev.bloodhound-py.overridePythonAttrs {
                      pname = "bloodhound";
                    }
                  );

            }
        )
      ];
  };
in
{
  unstable = import inputs.nixpkgs-unstable {
    system = final.stdenv.hostPlatform.system;
    config = {
      allowUnfree = true;
      android_sdk.accept_license = true;
      cudaCapabilities = prev.config.cudaCapabilities or [ ];
    } // prev.lib.optionalAttrs
      (prev.lib.elem "6.0" (prev.config.cudaCapabilities or [ ]))
      {
        # CUDA 13.x dropped offline compilation for Pascal (cc 6.0).
        # Pin the CUDA toolkit major version so ollama-cuda continues
        # to build with P100 support on hosts that have one.
        cudaVersion = "12";
      };
    overlays = [
      ollamaSplitGGUF
      pynfsclientMetadataVersion
    ];
  };
}
