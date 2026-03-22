{ pkgs, lib }:
args@{ ... }:
{ config, ... }:

{
  _module.args = {
    inherit args;
  };

  networking.nftables.enable = true;

  networking.nftables.ruleset =
    let
      markedLans = lib.filter (
        l:
        (l ? id)
        && (l.id >= 10)
      ) (args.lans or [ ]);
    in
    lib.mkMerge [
      ''
        table inet edge {
          chain classify {
            type filter hook prerouting priority -150;
      ''
      (lib.concatMapStrings (l: "    iifname \"${l.iface}\" meta mark set ${toString l.id}\n") markedLans)
      ''
          }
        }
      ''
    ];

  imports = [
    ./networkd.nix
    ./kea.nix
    ./kea-services.nix
    ./radvd.nix
    ./dns.nix
  ];
}
