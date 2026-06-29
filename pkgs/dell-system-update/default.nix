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

  dsuPublicKeys =
    let
      dellPgpPubkeys = "https://linux.dell.com/repo/pgp_pubkeys";
    in
    [
      {
        name = "0x756ba70b1019ced6.asc";
        src = fetchurl {
          url = "${dellPgpPubkeys}/0x756ba70b1019ced6.asc";
          hash = "sha256-4mIATd9NEQAqpYXmWgclusHnj7wJiloykMYXcge7UTg=";
        };
      }
      {
        name = "0x1285491434D8786F.asc";
        src = fetchurl {
          url = "${dellPgpPubkeys}/0x1285491434D8786F.asc";
          hash = "sha256-kvliK/MA8fyKTvEtjl7+9lEbCJxjwV5jXPx0KUmehtQ=";
        };
      }
      {
        name = "0xca77951d23b66a9d.asc";
        src = fetchurl {
          url = "${dellPgpPubkeys}/0xca77951d23b66a9d.asc";
          hash = "sha256-FPBk4Qe/XMp4JeS1dpFT7vkAq9V2LqvTfJ+4e/+jmpw=";
        };
      }
      {
        name = "0x3CA66B4946770C59.asc";
        src = fetchurl {
          url = "${dellPgpPubkeys}/0x3CA66B4946770C59.asc";
          hash = "sha256-dD13iAGsiIT51QPyHryQXq1x3dRF27pGyjRj76tyFKM=";
        };
      }
      {
        name = "0x076B95DB2FFC7F4A.asc";
        src = fetchurl {
          url = "${dellPgpPubkeys}/0x076B95DB2FFC7F4A.asc";
          hash = "sha256-G0dtxvOAhaKjWTZDPMWn7L2zAmUpxIsfA7BtRXFUVqc=";
        };
      }
      {
        name = "0x274E9C32857A9594.asc";
        src = fetchurl {
          url = "${dellPgpPubkeys}/0x274E9C32857A9594.asc";
          hash = "sha256-mUGS+9/BGauZ3MRTgkQvAXEegwpuhQ6gAVHm8jkF7Wo=";
        };
      }
    ];

  dsuPublicKeyDir = stdenv.mkDerivation {
    pname = "dell-dsu-public-keys";
    version = "2026-06-19";
    dontUnpack = true;

    installPhase =
      ''
        runHook preInstall
        mkdir -p "$out"
      ''
      + lib.concatMapStringsSep "\n"
        (key: ''
          install -m 0644 ${key.src} "$out/${key.name}"
        '')
        dsuPublicKeys
      + ''
        runHook postInstall
      '';
  };

  payload = stdenv.mkDerivation rec {
    pname = "dell-system-update-payload";
    version = "2.2.0.1";

    src = fetchurl {
      url = "https://linux.dell.com/repo/hardware/dsu/os_independent/x86_64/dell-system-update-2.2.0.1-26.03.00.x86_64.rpm";
      hash = "sha256-XNAphZMZ5jymOqbuy8YY5SL+vaTt9g8Oweq2AJ8n5hQ=";
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
      description = "Dell System Update payload";
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

  targetPkgs = _pkgs: [
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
    zlib
    zstd
  ];

  extraPreBwrapCmds = ''
    mkdir -p /var/cache/dell/dell_dup/dsu /var/cache/dell/dsu /var/cache/dell/dsu/opt /var/lib/dell/dsu
    ${rsync}/bin/rsync -a --delete ${payload}/opt/ /var/cache/dell/dsu/opt/
    for key in ${dsuPublicKeyDir}/*.asc; do
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
    description = "Dell System Update from Dell's official RPM, wrapped for NixOS";
    homepage = "https://linux.dell.com/repo/hardware/dsu/";
    license = lib.licenses.unfree;
    mainProgram = "dsu";
    platforms = [ "x86_64-linux" ];
  };
}
