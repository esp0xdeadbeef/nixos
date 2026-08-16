{ lib
, python3
, chromium
, writeShellApplication
}:

let
  python = python3.withPackages (ps: [ ps.websocket-client ]);
in
writeShellApplication {
  name = "cobalt-switch-bootstrap";
  runtimeInputs = [ python chromium ];
  text = ''
    exec python3 ${./bootstrap.py}
  '';
  meta = with lib; {
    description = "Drive the cobalt GS108PEv3 web UI (login + default-password change) via headless Chromium/CDP";
    mainProgram = "cobalt-switch-bootstrap";
  };
}
