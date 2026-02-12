# FILE: ./lib/debug/30-routing.nix
let
  pkgs = null;
  lib = import <nixpkgs/lib>;
  cfg = import ./inputs.nix;

  withNebula = import ./25-topology-with-nebula.nix;

  _requireSops =
    if !(builtins.hasAttr "sopsData" cfg) then
      throw ''
        debug/30-routing.nix: cfg.sopsData missing.

        You MUST run this via ./debug.sh
        which sets SOPS_WAN_FILE and injects decrypted WAN data.
      ''
    else if !(builtins.hasAttr "wan" cfg.sopsData) then
      throw "debug/30-routing.nix: cfg.sopsData.wan missing"
    else
      null;

  stripCidr = s: builtins.elemAt (lib.splitString "/" s) 0;

  mkWanLink =
    name: wan:
    let
      ip4 = if builtins.hasAttr "ip4" wan then "${stripCidr wan.ip4}/32" else null;

      ip6 = if builtins.hasAttr "ip6" wan then "${stripCidr wan.ip6}/128" else null;
    in
    {
      kind = "wan";
      carrier = "wan";
      vlanId = 6;
      name = "wan-${name}";
      members = [ "s-router-core-wan" ];
      endpoints = {
        "s-router-core-wan" = {
          routes4 = lib.optional (ip4 != null) {
            dst = "0.0.0.0/0";
          };

          routes6 = lib.optional (ip6 != null) {
            dst = "::/0";
          };
        }
        // lib.optionalAttrs (ip4 != null) { addr4 = ip4; }
        // lib.optionalAttrs (ip6 != null) { addr6 = ip6; };
      };
    };

  sopsWans = cfg.sopsData.wan;

  wanLinks = lib.mapAttrs (name: wan: mkWanLink name wan) sopsWans;

  withWan = withNebula // {
    links = withNebula.links // wanLinks;
  };

in
import ../routing-gen.nix {
  inherit lib;
  inherit (cfg) ulaPrefix tenantV4Base;
} withWan
