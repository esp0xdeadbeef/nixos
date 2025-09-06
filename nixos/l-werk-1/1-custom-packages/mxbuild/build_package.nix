{
  stdenv,
  lib,
  fetchurl,
  patchelf,
  makeWrapper,
  icu,
  openssl,
}:

stdenv.mkDerivation rec {
  pname = "mxbuild";
  version = "10.21.0.64362";

  src = fetchurl {
    url = "https://cdn.mendix.com/runtime/mxbuild-${version}.tar.gz";
    sha256 = "sha256-rH7goj4cDgEfzua2nY32kje8JJ50L39pLxXbdo976kA=";
  };

  nativeBuildInputs = [
    patchelf
    makeWrapper
  ];

  unpackPhase = "tar xzf $src";

  buildPhase = "true";

  installPhase = ''
    mkdir -p $out/bin
    mkdir -p $out/mendix-src

    # Copy the entire source tree.
    cp -r ./* $out/mendix-src/

    # Change directory to the copied sources.
    cd $out/mendix-src

    # Loop only over the files you want to patch.
    # (Adjust the grep pattern as necessary to select only the desired executables.)
    find . -type f -executable | grep -v '/node_modules/\|bin/lessc\|\.wasm$\|gradle\|node\|sass' | while read -r file; do
      # Get absolute path to the file.
      fullFile="$out/mendix-src/$file"

      # Optionally: create a symlink in $out/bin with the same basename.
      ln -s "$fullFile" "$out/bin/$(basename $file)"

      # Patch the binary.
      patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$fullFile"

      # Wrap the binary.
      wrapProgram "$fullFile" --prefix LD_LIBRARY_PATH : ${stdenv.cc.cc.lib}/lib:${icu}/lib:${openssl.out}/lib
    done
  '';

  meta = {
    description = "MxBuild - a tool to create a Mendix Deployment Package.";
    homepage = "https://mendix.com/";
    # license = can not find;
  };
}
