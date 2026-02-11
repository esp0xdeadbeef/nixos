# FILE: ./lib/debug/inputs.nix

let
  file = builtins.getEnv "SOPS_WAN_FILE";

  sopsData =
    if file == "" then
      throw ''
        debug/inputs.nix: SOPS_WAN_FILE not set.
        You MUST run via ./debug.sh
      ''
    else
      builtins.fromJSON (builtins.readFile file);

  base = import ../../inputs;

  #
  # Merge everything from sops into inputs.
  # SOPS values override base.
  #
  merged =
    if builtins.isFunction base then
      base { inherit sopsData; }
    else
      base // sopsData // { inherit sopsData; };

in
merged
