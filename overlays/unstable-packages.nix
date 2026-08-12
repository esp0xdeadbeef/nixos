{ inputs }: final: prev:
let
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

  # Hosts with old GPUs (e.g. P100 / Pascal cc 6.0) need custom CUDA
  # architectures that miss the binary cache.  When a host opts in via
  # nixpkgs.config.ollamaPinToStable, ollama is pinned to stable nixpkgs
  # to reduce rebuild churn; every other host tracks the latest unstable
  # release.
  pinOllama = prev.config.ollamaPinToStable or false;
in
{
  unstable = import inputs.nixpkgs-unstable {
    system = final.stdenv.hostPlatform.system;
    config = {
      allowUnfree = true;
      android_sdk.accept_license = true;
      cudaCapabilities = prev.config.cudaCapabilities or [ ];
    } // prev.lib.optionalAttrs pinOllama
      {
        # CUDA 13.x dropped offline compilation for Pascal (cc 6.0).
        # Pin the CUDA toolkit major version so ollama-cuda continues
        # to build with P100 support on hosts that have one.
        cudaVersion = "12";
      };
    overlays = [
      pynfsclientMetadataVersion
    ];
  };

  ollamaForHost =
    if pinOllama
    then prev.ollama-cuda
    else final.unstable.ollama-cuda;
}
