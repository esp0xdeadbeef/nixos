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

              anyio =
                let
                  expectedVersion = "4.14.2";
                  actualVersion =
                    pythonPrev.anyio.version
                      or (final.lib.getVersion pythonPrev.anyio.name);
                in
                assert final.lib.assertMsg (actualVersion == expectedVersion)
                  "anyio overlay expects ${expectedVersion}, got ${actualVersion}; revisit the TLS-test skip once nixpkgs (or a newer anyio) is used.";
                builtins.trace
                  "WARNING: local anyio test skip is active (test_tls_connectable and the context-manager/fileio unraisable tests fail on this CPython 3.12 ssl); remove once upstream fixes them."
                  (
                    pythonPrev.anyio.overridePythonAttrs (old: {
                      # anyio 4.14.2's own suite is incompatible with the
                      # CPython 3.12 `ssl` in this nixpkgs: test_tls_connectable
                      # passes server_hostname to a *server*-side TLS wrap,
                      # which CPython now rejects with
                      # "server_hostname can only be specified in client mode".
                      # The context-manager and fileio tests then trip over the
                      # resulting unraisable exceptions.  Skip only those tests
                      # (the other ~2595 still run) rather than disabling the
                      # whole check.
                      disabledTests =
                        (old.disabledTests or [ ])
                        ++ [
                          "test_tls_connectable"
                          "test_exception"
                          "test_rglob"
                        ];
                    })
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
