{ lib }:

let
  # Linux IFNAMSIZ is 16 including NUL => max 15 visible chars
  maxIf = 15;

  # Characters we want to normalize
  badChars = [
    " "
    "_"
    "."
    ":"
    "/"
    "\\"
    "+"
    "="
    "@"
    ","
    ";"
    "("
    ")"
    "["
    "]"
    "{"
    "}"
    "<"
    ">"
    "\""
    "'"
  ];

  # Replace all bad chars with "-"
  sanitize =
    s:
    let
      s1 = lib.toLower s;
      s2 = builtins.replaceStrings badChars (lib.genList (_: "-") (lib.length badChars)) s1;
      # Keep only [a-z0-9-]
      s3 = lib.concatStrings (
        lib.filter (c: (c >= "a" && c <= "z") || (c >= "0" && c <= "9") || (c == "-")) (
          lib.stringToCharacters s2
        )
      );
      # Collapse multiple dashes
      s4 = lib.replaceStrings [ "--" "---" "----" ] [ "-" "-" "-" ] s3;
    in
    lib.removeSuffix "-" (lib.removePrefix "-" s4);

  # Deterministic short hash (8 chars)
  shortHash = s: builtins.substring 0 8 (builtins.hashString "sha256" s);

  # Stable, kernel-safe interface name
  mkIfName =
    {
      prefix,
      seed,
      hint ? "",
    }:
    let
      h = shortHash seed;
      base = sanitize "${prefix}${hint}";
      reserved = (if base == "" then 0 else 1) + (lib.stringLength h);
      keep = maxIf - reserved;
      trimmed = if keep > 0 then builtins.substring 0 keep base else "";
      name = if trimmed == "" then "${prefix}${h}" else "${trimmed}-${h}";
    in
    builtins.substring 0 maxIf name;

in
{
  inherit mkIfName sanitize shortHash;
}
