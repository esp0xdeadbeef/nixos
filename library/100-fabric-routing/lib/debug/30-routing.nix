# lib/debug/30-routing.nix
let
  pkgs = import <nixpkgs> {};
  lib  = pkgs.lib;
  cfg  = import ./00-inputs.nix;

  # Base topology with nebula WANs injected
  withNebula =
    import ./25-topology-with-nebula.nix;

  # Add fake ISP WAN (existing behavior)
  withWan =
    withNebula // {
      links = withNebula.links // {
        fake-isp = {
          kind = "wan";
          carrier = "wan";
          vlanId = 6;
          name = "fake-isp";
          members = [ "s-router-core-wan" ];
          endpoints = {
            "s-router-core-wan" = {
              addr4 = "198.51.100.2/29";
              routes4 = [ { dst = "0.0.0.0/0"; via4 = "198.51.100.1"; } ];

              addr6 = "2001:db8:1234::2/48";
              routes6 = [ { dst = "::/0"; } ];
            };
          };
        };
      };
    };

in
import ../routing-gen.nix {
  inherit lib;
  inherit (cfg) ulaPrefix tenantV4Base;
} withWan

