{ lib
, stdenv
, fetchFromGitHub
, python3
, writeShellApplication
}:

let
  src = fetchFromGitHub {
    owner = "PotatoMania";
    repo = "prosafe-vlan-manager";
    rev = "8ce87e6cfd37eec922468dc9a859ed1fa3136d01";
    hash = "sha256-cvRe3q0aN65H4dKp/C/lkKQV+iYmtD1l8H5m679By+8=";
  };

  patchedSrc = stdenv.mkDerivation {
    name = "prosafe-vlan-manager-src";
    inherit src;
    patches = [
      ../../patches/prosafe-vlan-cobalt.patch
    ];
    buildPhase = "true";
    installPhase = "cp -r . \"$out\"";
  };

  python = python3.withPackages (ps: [
    ps.beautifulsoup4
    ps.click
    ps.pydantic
    ps.requests
    ps.typing-extensions
  ]);

in
writeShellApplication {
  name = "prosafe-vlan";
  runtimeInputs = [ python ];
  text = ''
    export PYTHONPATH="${patchedSrc}:''${PYTHONPATH:-}"
    exec python -m prosafe "$@"
  '';
  meta = with lib; {
    description = "Declarative 802.1Q VLAN manager for Netgear ProSAFE Plus switches";
    homepage = "https://github.com/PotatoMania/prosafe-vlan-manager";
    license = licenses.agpl3Only;
  };
}
