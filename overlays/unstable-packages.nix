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
      pynfsclientMetadataVersion
    ];
  };
}
