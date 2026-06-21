# This file defines overlays
{ inputs, outPath, ... }:
{
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import "${outPath}/pkgs" final.pkgs;

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications =
    final: prev:
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
      xlayoutdisplay = prev.xlayoutdisplay.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          "${outPath}/patches/xlayoutdisplay-max-resolution.patch"
        ];
      });

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

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.stdenv.hostPlatform.system;
      config = final.config // {
        allowUnfree = true;
      };
      overlays = [ ];
    };
  };
}
