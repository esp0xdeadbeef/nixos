{ inputs }: final: prev:
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
}
