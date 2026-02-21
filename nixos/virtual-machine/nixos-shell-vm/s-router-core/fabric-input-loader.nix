{
  config,
  outPath,
  pkgs,
  lib,
  fabricInputs,
  inputs,
  fabricDebug ? false,
  ...
}:

let
  nfc =
    if inputs ? nixos-network-compiler then
      inputs.nixos-network-compiler
    else
      throw "missing flake input: nixos-network-compiler";

  compiled = nfc.lib.evalNetwork fabricInputs;

  debugFile = "/tmp/fabric-debug.json";

  debugPayload = builtins.toJSON {
    raw = fabricInputs;
    compiled = compiled;
  };

  debugScript = ''
    mkdir -p /tmp
    cat > ${debugFile} <<'EOF'
${debugPayload}
EOF
  '';
in
{
  _module.args.fabricCompiled = compiled;

  system.activationScripts.fabricDebug =
    lib.mkIf fabricDebug {
      text = debugScript;
    };
}
