{ lib
, nodejs
, writeShellApplication
}:

writeShellApplication {
  name = "cobalt-switch-bootstrap";
  runtimeInputs = [ nodejs ];
  text = ''
    exec node ${./bootstrap.mjs}
  '';
  meta = with lib; {
    description = "Drive the cobalt GS108PEv3 web UI (login + default-password change) without a browser";
    mainProgram = "cobalt-switch-bootstrap";
  };
}
