{
  stdenv,
  fetchzip,
  autoPatchelfHook,
  glibc,
  lib,
}:

let
  # version = "v2.3.1-rc1";
  version = "v2.3.1";

  hashes = {
    "v2.3.1-rc1" = "sha256-B+qbkvhAWSkE8vkQMxVsqkwRdB9ZjumlcXKupwMXYQo=";
    "v2.3.1" = "sha256-qG+yYhjDvI578i7/qCv+S767W9YDbEJeQ7d++Pg0bH8=";
    # get the hash via `nix-build -A azurehound --show-trace`
    # "future" = lib.fakeSha256;
  };

  sha256 = lib.attrByPath [ version ] lib.fakeSha256 hashes;

  src = fetchzip {
    url = "https://github.com/SpecterOps/AzureHound/releases/download/${version}/AzureHound_${version}_linux_amd64.zip";
    inherit sha256;
  };
in
stdenv.mkDerivation {
  pname = "azurehound";
  inherit version src;

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ glibc ];

  installPhase = ''
    mkdir -p $out/bin
    ls -la
    cp azurehound $out/bin/
    chmod +x $out/bin/azurehound
  '';
}
