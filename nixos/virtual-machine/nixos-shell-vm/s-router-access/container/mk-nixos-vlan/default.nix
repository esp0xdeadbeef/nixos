{ pkgs, lib }:
args@{ ... }:
{ config, ... }:

let
  # Single-WAN default: mark LAN packets with WAN0 mark so ip rule matches.
  wans = args.wans or [ ];
  wan0 =
    if (builtins.length wans) > 0
    then builtins.elemAt wans 0
    else abort "mk-nixos-vlan/default.nix: args.wans must be non-empty";

  wanMark = toString (wan0.mark or (abort "mk-nixos-vlan/default.nix: WAN0 missing mark"));

  # LANs with id >= 10 (exclude WAN-ish LAN1010 if you keep that convention)
  markedLans = lib.filter (
    l:
    (l ? id)
    && (l.id >= 10)
    && !(l.iface == "lan1010")
  ) (args.lans or [ ]);

in
{
  _module.args = {
    inherit args;
  };

  # IMPORTANT: merge with other rulesets; don't clobber
  networking.nftables.ruleset = lib.mkAfter ''
    table inet edge {
      chain classify {
        type filter hook prerouting priority -150; policy accept;
${lib.concatMapStrings (l: ''
        iifname "${l.iface}" meta mark set ${wanMark}
'') markedLans}
      }
    }
  '';

  imports = [
    ./networkd.nix
    ./kea.nix
    ./kea-services.nix
    ./radvd.nix
    ./dns.nix
  ];
}

