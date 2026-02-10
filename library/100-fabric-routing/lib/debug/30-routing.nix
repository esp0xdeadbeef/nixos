# lib/debug/30-routing.nix
let
  pkgs = null;
  lib = import <nixpkgs/lib>;
  cfg = import ./inputs.nix;

  # Base topology with nebula WANs injected
  withNebula = import ./25-topology-with-nebula.nix;

  # Add fake ISP WAN (existing behavior)
  withWan = withNebula // {
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
            routes4 = [
              {
                dst = "192.168.1.0/24";
                via4 = "10.255.255.3";
              }
              {
                dst = "192.168.2.0/24";
                via4 = "10.255.255.3";
              }
              {
                dst = "10.13.37.0/24";
                via4 = "10.255.255.3";
              }
              # other properties will be added here.
            ];

            addr6 = "2001:db8:1234::2/48";
            routes6 = [
              {
                dst = "2001:db8:1234:10::/56";
                via6 = "fd42:dead:beef:1010::3";
              }
            ];
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
