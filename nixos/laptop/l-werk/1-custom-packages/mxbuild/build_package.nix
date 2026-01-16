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
  # go to https://marketplace.mendix.com/link/studiopro
  # start a download (for windows for example, and cancel the download)
  # copy the version in the download url.
  version = "10.24.9.81004";

  src = fetchurl {
    url = "https://cdn.mendix.com/runtime/mxbuild-${version}.tar.gz";
    #sha256 = "sha256-rH7goj4cDgEfzua2nY32kje8JJ50L39pLxXbdo976kA=";
    # get the hash by:
    # nix store prefetch-file https://cdn.mendix.com/runtime/mxbuild-10.24.9.81004.tar.gz
    sha256 = "sha256-mJEmlZmVeo6n5tXs4ta0lKTr5HAKRNeq4ehm1vP7SuY=";
  };

  nativeBuildInputs = [
    patchelf
    makeWrapper
  ];

  unpackPhase = "tar xzf $src";

  buildPhase = "true";

  installPhase = ''
    mkdir -p $out/mendix-src

    # Copy the entire source tree.
    cp -r ./* $out/mendix-src/

    mkdir -p $out/bin

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
