{ autoPatchelfHook
, buildFHSEnv
, coreutils
, curl
, dmidecode
, fetchurl
, file
, findutils
, gawk
, gcc
, gnupg
, gpgme
, ipmitool
, kmod
, lib
, libuuid
, libxml2_13
, makeWrapper
, pciutils
, rpm
, rpmextract
, rsync
, stdenv
, usbutils
, which
, zlib
, zstd
}:

let
  dellPgpPubkeys = "https://linux.dell.com/repo/pgp_pubkeys";
  dellBanner = "DELL FIRMWARE TOOLING IS PAINFUL";

  gpgmeCompat = gpgme.overrideAttrs (_old: {
    version = "1.24.3";

    src = fetchurl {
      url = "mirror://gnupg/gpgme/gpgme-1.24.3.tar.bz2";
      hash = "sha256-v8F/W9GxeMhkn92RiVbSdwgPM98Aai3ECs3s3OaMUN0=";
    };

    patches = [ ];
    doCheck = false;
    passthru = { };
  });

  payload = stdenv.mkDerivation rec {
    pname = "dell-system-update-payload";
    version = "2.3.0.0";

    src = fetchurl {
      url = "https://linux.dell.com/repo/hardware/dsu/os_independent/x86_64/dell-system-update-2.3.0.0-26.07.00.x86_64.rpm";
      hash = "sha256-8+YZmmBM346/K5RIHljdTAuQ87N/r4oTBJS74eF7FN4=";
    };

    nativeBuildInputs = [
      autoPatchelfHook
      makeWrapper
      rpmextract
    ];

    buildInputs = [
      gcc.cc.lib
      gpgmeCompat
      libuuid
      libxml2_13
      zlib
      zstd
    ];

    unpackPhase = ''
      runHook preUnpack
      rpmextract "$src"
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cp -a opt usr "$out/"
      mkdir -p "$out/usr/libexec/dell_dup"
      touch "$out/usr/libexec/dell_dup/.keep"

      mkdir -p "$out/bin"
      makeWrapper "$out/usr/sbin/dsu" "$out/bin/dsu" \
        --prefix PATH : ${lib.makeBinPath [
          coreutils
          curl
          dmidecode
          file
          findutils
          gawk
          gnupg
          ipmitool
          pciutils
          rpm
          usbutils
          which
        ]}

      runHook postInstall
    '';

    preFixup = ''
      addAutoPatchelfSearchPath "$out/usr/lib64/dsulib"
    '';

    meta = {
      description = "Dell System Update payload from a frustrating firmware vendor";
      homepage = "https://linux.dell.com/repo/hardware/dsu/";
      license = lib.licenses.unfree;
      platforms = [ "x86_64-linux" ];
    };
  };
in
buildFHSEnv {
  name = "dell-system-update-${payload.version}";
  executableName = "dsu";
  runScript = "/usr/bin/dsu";

  targetPkgs = pkgs: [
    payload
    coreutils
    curl
    dmidecode
    file
    findutils
    gawk
    gnupg
    gpgmeCompat
    gcc.cc.lib
    ipmitool
    kmod
    libuuid
    libxml2_13
    pciutils
    rpm
    rpmextract
    rsync
    usbutils
    which
    pkgs.xterm
    zlib
    zstd
  ];

  extraPreBwrapCmds = ''
    printf '%s\n' '${dellBanner}' >&2

    ${coreutils}/bin/mkdir -p /var/cache/dell/dell_dup/dsu /var/cache/dell/dsu /var/cache/dell/dsu/opt /var/lib/dell/dsu
    ${rsync}/bin/rsync -a --delete ${payload}/opt/ /var/cache/dell/dsu/opt/
    key_cache_dir=/var/cache/dell/dsu/pgp_pubkeys
    key_target_dir=/var/cache/dell/dell_dup/dsu
    ${coreutils}/bin/mkdir -p "$key_cache_dir" "$key_target_dir"

    has_cached_key() {
      [ -n "$(${findutils}/bin/find "$key_cache_dir" -maxdepth 1 -type f -name '*.asc' -print -quit)" ]
    }

    refresh_dell_dsu_keys() {
      tmp_dir=$(${coreutils}/bin/mktemp -d /tmp/dell-dsu-keys.XXXXXX)
      index_file="$tmp_dir/index.html"
      fingerprints_file="$tmp_dir/fingerprints.txt"
      key_names_file="$tmp_dir/key-names"
      failed=0

      if ! ${curl}/bin/curl -fsSL --retry 3 --retry-delay 2 -o "$index_file" "${dellPgpPubkeys}/"; then
        echo "dsu: warning: failed to fetch Dell PGP key index from ${dellPgpPubkeys}/" >&2
        ${coreutils}/bin/rm -rf "$tmp_dir"
        return 1
      fi

      if ! ${curl}/bin/curl -fsSL --retry 3 --retry-delay 2 -o "$fingerprints_file" "${dellPgpPubkeys}/fingerprints.txt"; then
        echo "dsu: warning: failed to fetch Dell PGP key fingerprints from ${dellPgpPubkeys}/fingerprints.txt" >&2
        ${coreutils}/bin/rm -rf "$tmp_dir"
        return 1
      fi

      ${gawk}/bin/awk '
        FILENAME == ARGV[1] {
          line = $0
          while (match(line, /href="([^"]+\.asc)"/, match_parts)) {
            name = match_parts[1]
            lookup = tolower(name)
            sub(/^0x/, "", lookup)
            sub(/\.asc$/, "", lookup)
            href[lookup] = name
            line = substr(line, RSTART + RLENGTH)
          }
          next
        }

        FILENAME == ARGV[2] {
          line = $0
          gsub(/[[:space:]]/, "", line)
          if (line ~ /Keyfingerprint=/) {
            sub(/.*Keyfingerprint=/, "", line)
            lookup = tolower(substr(line, length(line) - 15))
            if (lookup in href) {
              print href[lookup]
            }
          }
        }
      ' "$index_file" "$fingerprints_file" | ${coreutils}/bin/sort -u > "$key_names_file"

      if [ ! -s "$key_names_file" ]; then
        echo "dsu: warning: Dell PGP key mirror did not expose any DSU fingerprints" >&2
        ${coreutils}/bin/rm -rf "$tmp_dir"
        return 1
      fi

      while IFS= read -r key_name; do
        [ -n "$key_name" ] || continue
        if ${curl}/bin/curl -fsSL --retry 3 --retry-delay 2 -o "$tmp_dir/$key_name" "${dellPgpPubkeys}/$key_name"; then
          ${coreutils}/bin/install -m 0644 "$tmp_dir/$key_name" "$key_cache_dir/$key_name"
        else
          echo "dsu: warning: failed to fetch Dell PGP key $key_name" >&2
          failed=1
        fi
      done < "$key_names_file"

      ${coreutils}/bin/rm -rf "$tmp_dir"
      [ "$failed" -eq 0 ]
    }

    if [ "''${DELL_DSU_REFRESH_KEYS:-0}" = "1" ] || ! has_cached_key; then
      if ! refresh_dell_dsu_keys && ! has_cached_key; then
        echo "dsu: warning: no Dell PGP keys are cached; DSU may need network access or key import" >&2
      fi
    fi

    for key in "$key_cache_dir"/*.asc; do
      [ -e "$key" ] || continue
      target="/var/cache/dell/dell_dup/dsu/$(${coreutils}/bin/basename "$key")"
      ${coreutils}/bin/install -m 0644 "$key" "$target"
    done
  '';

  extraBuildCommands = ''
    mkdir -p "$out/usr/libexec/dell_dup"
    touch "$out/usr/libexec/dell_dup/.keep"
  '';

  extraBwrapArgs = [
    "--bind /var/cache/dell/dell_dup/dsu /usr/libexec/dell_dup"
    "--bind /var/cache/dell/dsu/opt /opt"
  ];

  meta = {
    description = "Dell System Update from Dell's official RPM; Dell firmware tooling is painful, wrapped for NixOS";
    homepage = "https://linux.dell.com/repo/hardware/dsu/";
    license = lib.licenses.unfree;
    mainProgram = "dsu";
    platforms = [ "x86_64-linux" ];
  };
}
