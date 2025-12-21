{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  # Use the same system as your current pkgs to avoid cross-system eval issues
  unstablePkgs = import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
  };

  # SecLists via the wordlists meta-package (as you did before), but from unstable
  wl = unstablePkgs.wordlists.override {
    lists = [ unstablePkgs.seclists ];
  };

  # PayloadsAllTheThings (separate package, not part of wordlists)
  patt = unstablePkgs.payloadsallthethings;
in
{
  environment.systemPackages = [
    wl
    patt
  ];

  # Impermanence-friendly stable paths recreated at boot
  systemd.tmpfiles.rules = [
    "L+ /usr/share/seclists - - - - ${wl}/share/wordlists/seclists"
    "L+ /usr/share/PayloadsAllTheThings - - - - ${patt}/share/payloadsallthethings"
  ];

  # Optional convenience env vars
  environment.variables = {
    SECLISTS = "/usr/share/seclists";
    PAYLOADSALLTHETHINGS = "/usr/share/PayloadsAllTheThings";
  };
}
