{ lib
, stdenv
, fetchFromGitHub
, python3
, makeWrapper
}:

stdenv.mkDerivation rec {
  pname = "netgear-admin";
  version = "unstable-2025-05-26";

  src = fetchFromGitHub {
    owner = "ElectricLab";
    repo = "netgear_admin";
    rev = "684c6d7c88d801f89920d3cd9642671e196f3c1f";
    hash = "sha256-WV1A8GLeLhYdfheHq1IQ4Z3hX2RHD1N/zVCCw11Unno=";
  };

  patches = [
    ../../patches/netgear_admin-gs108pev3.patch
  ];

  nativeBuildInputs = [ makeWrapper ];

  buildInputs = [ python3 ];

  installPhase = ''
    runHook preInstall
    install -Dm755 netgear_admin.py "$out/bin/netgear-admin"
    sed -i '1i #!/usr/bin/env python3' "$out/bin/netgear-admin"
    wrapProgram "$out/bin/netgear-admin" --prefix PATH : ${python3}/bin
    runHook postInstall
  '';

  meta = with lib; {
    description = "Netgear Plus switch port status/enable/disable/reboot helper";
    homepage = "https://github.com/ElectricLab/netgear_admin";
    license = licenses.mit;
    mainProgram = "netgear-admin";
  };
}
