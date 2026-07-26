# This file defines overlays
{ inputs
, relativeRepo
, ...
}: {
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: prev:
    import (relativeRepo.module "pkgs") {
      pkgs = final;
      inherit (prev) lib;
      system = prev.stdenv.hostPlatform.system;
    };

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev:
    let
      libvirtCredentialInit = final.writeShellScript "virt-secret-init-encryption-workaround" ''
        set -euo pipefail

        key=/var/lib/libvirt/secrets/secrets-encryption-key
        conf=/var/lib/libvirt/secret.conf

        ${final.coreutils}/bin/install -d -m 0700 -o root -g root "$(${final.coreutils}/bin/dirname "$key")"

        if [ -e "$key" ] && [ "$(${final.coreutils}/bin/stat -c %s "$key")" != 32 ]; then
          ${final.coreutils}/bin/mv -f "$key" "$key.invalid-raw-key.$(${final.coreutils}/bin/date +%s)"
        fi

        if [ ! -e "$key" ]; then
          ${final.coreutils}/bin/dd if=/dev/urandom of="$key" bs=32 count=1 status=none
        fi

        ${final.coreutils}/bin/chown root:root "$key"
        ${final.coreutils}/bin/chmod 0400 "$key"

        ${final.coreutils}/bin/printf 'secrets_encryption_key = "%s"\n' "$key" > "$conf.tmp"
        ${final.coreutils}/bin/install -m 0644 -o root -g root "$conf.tmp" "$conf"
        ${final.coreutils}/bin/rm -f "$conf.tmp"
      '';
    in
    {
      navi = inputs.cheat-sheets.packages.${final.stdenv.hostPlatform.system}.navi;

      xlayoutdisplay =
        let
          expectedVersion = "1.5.1";
          actualVersion = prev.xlayoutdisplay.version or (final.lib.getVersion prev.xlayoutdisplay.name);
        in
        assert final.lib.assertMsg (actualVersion == expectedVersion)
          "xlayoutdisplay overlay expects ${expectedVersion}, got ${actualVersion}; review patches/xlayoutdisplay-max-resolution.patch before updating xlayoutdisplay.";
        prev.xlayoutdisplay.overrideAttrs (old: {
          patches =
            (old.patches or [ ])
            ++ [
              # Keep patches as narrow source dependencies so unrelated repository
              # changes do not force this package to rebuild.
              ../patches/xlayoutdisplay-max-resolution.patch
              ../patches/xlayoutdisplay-display-selectors.patch
            ];
        });

      xlayoutdisplay-selectors = final.writeShellApplication {
        name = "xlayoutdisplay-selectors";
        runtimeInputs = [
          final.gawk
          final.xlayoutdisplay
        ];
        text = ''
          xlayoutdisplay --info | awk '
            /^[^[:space:]].* (active|connected)/ {
              output = $1
              selectors = ""
              for (i = 1; i <= NF; i++) {
                if ($i ~ /^[[:alnum:]]+:[[:alnum:]][[:alnum:]:]*$/ || $i ~ /^edid:[[:xdigit:]]+$/) {
                  selectors = selectors " " $i
                }
              }
              if (selectors != "") {
                print output selectors
              }
            }
          '
        '';
      };

      libvirt =
        builtins.trace
          "WARNING: local libvirt credential workaround overlay is active; remove it once nixpkgs fixes the 26.05 LoadCredentialEncrypted libvirt regression."
          (
            final.runCommand "${prev.libvirt.name}-credential-workaround"
              {
                inherit (prev.libvirt) meta passthru;
                preferLocalBuild = true;
              }
              ''
                ${final.coreutils}/bin/mkdir -p "$out"
                ${final.coreutils}/bin/cp -a ${prev.libvirt}/. "$out/"

                for unit in \
                  "$out/lib/systemd/system/libvirtd.service" \
                  "$out/lib/systemd/system/virtsecretd.service"
                do
                  substituteInPlace "$unit" \
                    --replace-fail \
                      'Environment=SECRETS_ENCRYPTION_KEY=%d/secrets-encryption-key' \
                      'Environment=SECRETS_ENCRYPTION_KEY=/var/lib/libvirt/secrets/secrets-encryption-key' \
                    --replace-fail \
                      'LoadCredentialEncrypted=secrets-encryption-key:/var/lib/libvirt/secrets/secrets-encryption-key' \
                      ""
                done

                ${final.coreutils}/bin/chmod u+w "$out/lib/systemd/system/virt-secret-init-encryption.service"
                cat > "$out/lib/systemd/system/virt-secret-init-encryption.service" <<EOF
                [Unit]
                Before=virtsecretd.service
                Before=libvirtd.service

                [Service]
                Type=oneshot
                ExecStart=${libvirtCredentialInit}
                EOF
              ''
          );
    };

  legcord-unstable-overwrite = final: _prev: {
    # Explicit overwrite: keep legcord on unstable until the stable package set
    # carries the same fixed dependency graph.
    legcord =
      builtins.trace
        "WARNING: local legcord overlay is active: pkgs.legcord = pkgs.unstable.legcord."
        final.unstable.legcord;
  };

  impermanence-module = final: _prev: {
    impermanenceNixosModule =
      args @ { config
      , lib
      , pkgs
      , ...
      }:
      let
        patchedLib =
          lib
          // {
            mkRemovedOptionModule = optionName: replacementInstructions:
              if optionName == [ "method" ]
              then _moduleArgs: { }
              else lib.mkRemovedOptionModule optionName replacementInstructions;
          };

        nixosUtils = import "${inputs.nixpkgs}/nixos/lib/utils.nix" {
          inherit config lib pkgs;
        };

        upstreamModule = inputs.impermanence.nixosModules.impermanence (
          args
          // {
            lib = patchedLib;
            utils = nixosUtils;
          }
        );
      in
      upstreamModule
      // {
        config = lib.mkMerge [
          (upstreamModule.config or { })
          {
            warnings = [
              "Using local impermanence module overlay: directory submodules currently trip the removed 'method' option on NixOS 26.05."
            ];
          }
        ];
      };
  };

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev:
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
    in
    {
      unstable = import inputs.nixpkgs-unstable {
        system = final.stdenv.hostPlatform.system;
        config =
          final.config
          // {
            allowUnfree = true;
          };
        overlays = [ ollamaSplitGGUF ];
      };
    };
}
