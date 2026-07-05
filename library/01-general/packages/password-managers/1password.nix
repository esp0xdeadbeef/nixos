{ config
, lib
, pkgs
, ...
}:
let
  primaryUser = config.local.users.primary.resolvedName;
  onePasswordPkgs = pkgs.unstable or pkgs;
in
{
  # Enable the unfree 1Password packages
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "1password-gui"
      "1password"
      "1password-cli"
    ];
  # Alternatively, you could also just allow all unfree packages
  # nixpkgs.config.allowUnfree = true;

  programs._1password = {
    enable = true;
    package = onePasswordPkgs._1password-cli;
  };

  programs._1password-gui = {
    enable = true;
    package = onePasswordPkgs._1password-gui;
    # Certain features, including CLI integration and system authentication support,
    # require enabling PolKit integration on some desktop environments (e.g. Plasma).
    polkitPolicyOwners = lib.mkIf (primaryUser != null) [ primaryUser ];
  };
}
