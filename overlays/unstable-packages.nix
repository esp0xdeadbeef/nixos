{ inputs }: final: prev:
let
  ollamaSplitGGUF = _unstableFinal: unstablePrev:
    let
      expectedVersion = "0.32.1";
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
        let
          actualVersion = package.version or (final.lib.getVersion package.name);
        in
        assert final.lib.assertMsg (actualVersion == expectedVersion)
          "Ollama split-GGUF overlay expects ${expectedVersion}, got ${actualVersion}; review patches/ollama-hf-sharded-gguf.patch before updating Ollama.";
        package.overrideAttrs (
          old:
          {
            patches =
              (old.patches or [ ])
              ++ [
                # Hugging Face currently rejects its Ollama manifest endpoint
                # for sharded GGUFs. Fall back to the Hub API, download every
                # content-addressed shard, and feed them through Ollama's
                # existing split-GGUF importer.
                ../patches/ollama-hf-sharded-gguf.patch
              ];
          }
          // final.lib.optionalAttrs cuda {
            # setupCudaHook exposes the splayed CUDA outputs as a
            # semicolon-separated CUDAToolkit_ROOT. Ollama 0.32.1 passes
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
              expectedVersion = "1.0.6";
              actualVersion =
                pythonPrev.pynfsclient.version
                  or (final.lib.getVersion pythonPrev.pynfsclient.name);
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

              pynfsclient =
                assert final.lib.assertMsg (actualVersion == expectedVersion)
                  "pynfsclient overlay expects ${expectedVersion}, got ${actualVersion}; remove the metadata fix once upstream updates pyNfsClient/__info__.py.";
                builtins.trace
                  "WARNING: local pynfsclient metadata workaround is active; remove it once upstream reports version ${expectedVersion}."
                  (
                    pythonPrev.pynfsclient.overridePythonAttrs (old: {
                      postPatch =
                        (old.postPatch or "")
                        + ''
                          substituteInPlace pyNfsClient/__info__.py \
                            --replace-fail \
                              '__version__ = "0.1.5"' \
                              '__version__ = "${expectedVersion}"'
                        '';
                    })
                  );

              stamina =
                let
                  expectedVersion = "25.2.0";
                  actualVersion =
                    pythonPrev.stamina.version
                      or (final.lib.getVersion pythonPrev.stamina.name);
                in
                assert final.lib.assertMsg (actualVersion == expectedVersion)
                  "stamina overlay expects ${expectedVersion}, got ${actualVersion}; remove the test-ID fix once upstream uses unique parametrization IDs.";
                builtins.trace
                  "WARNING: local stamina pytest workaround is active; remove it once upstream uses unique parametrization IDs."
                  (
                    pythonPrev.stamina.overridePythonAttrs (old: {
                      postPatch =
                        (old.postPatch or "")
                        + ''
                          substituteInPlace tests/test_instrumentation.py \
                            --replace-fail \
                              '            (Foo.method, "test_instrumentation.Foo.method"),' \
                              '            pytest.param(Foo.method, "test_instrumentation.Foo.method", id="Foo.method-unbound"),' \
                            --replace-fail \
                              '            (Foo.async_method, "test_instrumentation.Foo.async_method"),' \
                              '            pytest.param(Foo.async_method, "test_instrumentation.Foo.async_method", id="Foo.async_method-unbound"),'
                        '';
                    })
                  );

              mitmproxy =
                let
                  expectedVersion = "12.2.3";
                  actualVersion =
                    pythonPrev.mitmproxy.version
                      or (final.lib.getVersion pythonPrev.mitmproxy.name);
                in
                assert final.lib.assertMsg (actualVersion == expectedVersion)
                  "mitmproxy overlay expects ${expectedVersion}, got ${actualVersion}; remove the msgpack relaxation once nixpkgs relaxes the upstream upper bound.";
                builtins.trace
                  "WARNING: local mitmproxy msgpack workaround is active; remove it once nixpkgs relaxes the upstream upper bound."
                  (
                    pythonPrev.mitmproxy.overridePythonAttrs (old: {
                      pythonRelaxDeps =
                        (old.pythonRelaxDeps or [ ])
                        ++ [ "msgpack" ];
                    })
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
    };
    overlays = [
      ollamaSplitGGUF
      pynfsclientMetadataVersion
    ];
  };
}
