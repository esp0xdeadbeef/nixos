# lib/debug/debug-eval.nix
let
  pkgs = null;
  lib = import <nixpkgs/lib>;

  ulaPrefix = "fd42:dead:beef";
  tenantV4Base = "10.10";

  raw = import ../topology-gen.nix { inherit lib; } {
    tenantVlans = [
      10
      20
      30
      40
      50
      60
      70
      80
    ];
    policyAccessTransitBase = 100;
    corePolicyTransitVlan = 200;
  };

  resolved = import ../topology-resolve.nix {
    inherit lib ulaPrefix tenantV4Base;
  } raw;

  routed =
    import ../routing-gen.nix
      {
        inherit lib ulaPrefix tenantV4Base;
      }
      (
        resolved
        // {
          links = resolved.links // {
            fake-isp = {
              kind = "wan";
              carrier = "wan";
              vlanId = 6;
              name = "fake-isp";
              members = [ "s-router-core-wan" ];
              endpoints = {
                "s-router-core-wan" = {
                  addr6 = "2001:db8::2/48";
                  routes6 = [ { dst = "::/0"; } ];
                };
              };
            };
          };
        }
      );

in
{
  topology = {
    domain = routed.domain;
    nodes = lib.attrNames routed.nodes;
    links = lib.attrNames routed.links;
  };

  nodes = lib.mapAttrs (
    n: _:
    import ./view-node.nix {
      inherit
        lib
        pkgs
        ulaPrefix
        tenantV4Base
        ;
    } n routed
  ) routed.nodes;
}
