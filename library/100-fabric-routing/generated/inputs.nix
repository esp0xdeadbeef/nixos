{
  lib ? null,
}:

let
  outPath = builtins.getEnv "outPath";

  secretsFile = "${outPath}/secrets/s-routers-public-ips.yaml";

  sopsData =
    if builtins.pathExists secretsFile then builtins.fromJSON (builtins.readFile secretsFile) else { };

  base = import ../inputs;

  merged =
    if builtins.isFunction base then
      base { inherit sopsData; }
    else
      base // sopsData // { inherit sopsData; };

in
merged
