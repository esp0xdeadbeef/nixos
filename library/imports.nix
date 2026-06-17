{ lib }:
let
  disabledPrefixes = [
    "build_"
    "disabled_"
  ];

  hasDisabledPrefix = name: lib.any (prefix: lib.hasPrefix prefix name) disabledPrefixes;

  isNixModuleFile = name: lib.hasSuffix ".nix" name && !lib.hasSuffix ".bak" name;

  isDirectImportable =
    dir: name: type:
    !hasDisabledPrefix name
    && (
      (type == "regular" && isNixModuleFile name && name != "default.nix")
      || (type == "directory" && builtins.pathExists (dir + "/${name}/default.nix"))
    );

  enabledEntryNames =
    dir:
    let
      entries = if builtins.pathExists dir then builtins.readDir dir else { };
      names = lib.sort builtins.lessThan (builtins.attrNames entries);
    in
    lib.filter (name: !hasDisabledPrefix name) names;

  recursiveImports =
    dir:
    lib.flatten (
      map (
        name:
        let
          path = dir + "/${name}";
          type = (builtins.readDir dir).${name};
        in
        if type == "regular" && isNixModuleFile name && name != "default.nix" then
          [ path ]
        else if type == "directory" then
          if builtins.pathExists (path + "/default.nix") then [ path ] else recursiveImports path
        else
          [ ]
      ) (enabledEntryNames dir)
    );
in
{
  inherit disabledPrefixes hasDisabledPrefix;

  enabledImports =
    dir:
    let
      entries = if builtins.pathExists dir then builtins.readDir dir else { };
      names = lib.sort builtins.lessThan (builtins.attrNames entries);
      enabledNames = lib.filter (name: isDirectImportable dir name entries.${name}) names;
    in
    map (name: dir + "/${name}") enabledNames;

  enabledImportsRecursive = recursiveImports;
}
