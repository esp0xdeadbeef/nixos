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
, lib
, libuuid
, libxml2_13
, makeWrapper
, pciutils
, rpmextract
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
    ipmitool
    libxml2_13
    pciutils
    rpmextract
    usbutils
    which
  ];

  extraPreBwrapCmds = ''
    mkdir -p /tmp/dell-system-update-dell_dup
  '';

  extraBuildCommands = ''
    mkdir -p "$out/usr/libexec/dell_dup"
    touch "$out/usr/libexec/dell_dup/.keep"
  '';

  extraBwrapArgs = [
    "--bind /tmp/dell-system-update-dell_dup /usr/libexec/dell_dup"
  ];

  meta = {
    description = "Dell System Update from Dell's official RPM, wrapped for NixOS";
    homepage = "https://linux.dell.com/repo/hardware/dsu/";
    license = lib.licenses.unfree;
    mainProgram = "dsu";
    platforms = [ "x86_64-linux" ];
  };
}
