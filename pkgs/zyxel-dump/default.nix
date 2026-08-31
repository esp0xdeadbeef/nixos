{ lib
, writeShellApplication
, nodejs
}:

writeShellApplication {
  name = "zyxel-dump";
  runtimeInputs = [ nodejs ];
  text = ''
    if [ -z "''${ZYXEL_PASSWORD:-}" ]; then
      echo "ZYXEL_PASSWORD is not set; export it from sops first:" >&2
      echo "  export ZYXEL_PASSWORD=\$(sops --decrypt --extract '[\"password\"]' secrets/s-router-cobalt-zyxel-admin-password.yaml)" >&2
      exit 1
    fi
    exec node ${../../prod-network/cobalt/zyxel-dump.mjs} "$@"
  '';
  meta = with lib; {
    description = "Read-only ZyXEL EX7501-B0 config dump (login + DAL enumeration)";
  };
}
