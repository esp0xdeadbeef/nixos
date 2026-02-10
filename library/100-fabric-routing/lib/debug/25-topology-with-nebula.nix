# lib/debug/25-topology-with-nebula.nix
let
  pkgs = null;
  lib = import <nixpkgs/lib>;

  base = import ./20-topology-resolved.nix;

in
base
// {
  links = base.links // {

    # ─────────────────────────────────────────────
    # Nebula WAN exits (one per plane)
    # Treated exactly like external WANs
    # ─────────────────────────────────────────────

    nebula-control = {
      kind = "wan";
      carrier = "nebula";
      vlanId = 1010;
      name = "nebula-control";
      members = [ "s-nebula-control" ];

      endpoints = {
        "s-nebula-control" = {
          addr4 = "100.64.10.2/32";
          routes4 = [ { dst = "0.0.0.0/0"; } ];

          addr6 = "fd00:10::2/128";
          routes6 = [ { dst = "::/0"; } ];
        };
      };
    };

    nebula-service = {
      kind = "wan";
      carrier = "nebula";
      vlanId = 1020;
      name = "nebula-service";
      members = [ "s-nebula-service" ];

      endpoints = {
        "s-nebula-service" = {
          addr4 = "100.64.20.2/32";
          routes4 = [ { dst = "0.0.0.0/0"; } ];

          addr6 = "fd00:20::2/128";
          routes6 = [ { dst = "::/0"; } ];
        };
      };
    };

    nebula-lab = {
      kind = "wan";
      carrier = "nebula";
      vlanId = 1070;
      name = "nebula-lab";
      members = [ "s-nebula-lab" ];

      endpoints = {
        "s-nebula-lab" = {
          addr4 = "100.64.70.2/32";
          routes4 = [ { dst = "0.0.0.0/0"; } ];

          addr6 = "fd00:70::2/128";
          routes6 = [ { dst = "::/0"; } ];
        };
      };
    };
  };

  # Also inject the nebula nodes so debug views don’t explode
  nodes = base.nodes // {
    "s-nebula-control" = {
      ifs = {
        nebula = "nebula0";
      };
    };
    "s-nebula-service" = {
      ifs = {
        nebula = "nebula0";
      };
    };
    "s-nebula-lab" = {
      ifs = {
        nebula = "nebula0";
      };
    };
  };
}
