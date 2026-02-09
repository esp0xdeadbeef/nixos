{ lib }:

let
  inRange = r: vid: vid >= r.from && vid <= r.to;

  fabrics = [
    {
      key = "legacy";
      range = {
        from = 2;
        to = 9;
      };
      plane = "legacy";
      trust = "none";
      role = "legacy/quarantine";
      defaults = {
        kind = "lan";
        dhcp4 = true;
        ra6 = false;
        routable = true;
        transit = false;
        dns = true;
        reverseDns = false;
        mtu = 1500;
      };
    }

    {
      key = "control";
      range = {
        from = 10;
        to = 19;
      };
      plane = "control";
      trust = "absolute";
      role = "authority+recovery";
      defaults = {
        kind = "lan";
        dhcp4 = true;
        ra6 = true;
        routable = true;
        transit = false;
        dns = true;
        reverseDns = true;
        mtu = 1500;
      };
    }

    {
      key = "service";
      range = {
        from = 20;
        to = 29;
      };
      plane = "service";
      trust = "limited";
      role = "shared-services";
      defaults = {
        kind = "lan";
        dhcp4 = true;
        ra6 = true;
        routable = true;
        transit = false;
        dns = true;
        reverseDns = true;
        mtu = 1500;
      };
    }

    {
      key = "endpoint";
      range = {
        from = 30;
        to = 39;
      };
      plane = "endpoint";
      trust = "untrusted";
      role = "human-devices";
      defaults = {
        kind = "lan";
        dhcp4 = true;
        ra6 = true;
        routable = true;
        transit = false;
        dns = true;
        reverseDns = true;
        mtu = 1500;
      };
    }

    {
      key = "corp";
      range = {
        from = 40;
        to = 49;
      };
      plane = "corp";
      trust = "semi-hostile";
      role = "regulated";
      defaults = {
        kind = "lan";
        dhcp4 = true;
        ra6 = true;
        routable = true;
        transit = false;
        dns = true;
        reverseDns = true;
        mtu = 1500;
      };
    }

    {
      key = "iot";
      range = {
        from = 50;
        to = 59;
      };
      plane = "iot";
      trust = "hostile";
      role = "untrusted-devices";
      defaults = {
        kind = "lan";
        dhcp4 = true;
        ra6 = true;
        routable = true;
        transit = false;
        dns = true;
        reverseDns = true;
        mtu = 1500;
      };
    }

    {
      key = "dmz";
      range = {
        from = 60;
        to = 69;
      };
      plane = "dmz";
      trust = "exposed";
      role = "public-services";
      defaults = {
        kind = "lan";
        dhcp4 = false;
        ra6 = false;
        routable = true;
        transit = false;
        dns = true;
        reverseDns = true;
        mtu = 1500;
      };
    }

    {
      key = "lab";
      range = {
        from = 70;
        to = 79;
      };
      plane = "lab";
      trust = "actively-hostile";
      role = "adversarial";
      defaults = {
        kind = "lan";
        dhcp4 = true;
        ra6 = true;
        routable = true;
        transit = false;
        dns = true;
        reverseDns = true;
        mtu = 1500;
      };
    }
    {
      key = "observability";
      range = {
        from = 80;
        to = 89;
      };
      plane = "observability";
      trust = "limited";
      role = "telemetry";
      defaults = {
        kind = "lan";
        dhcp4 = false; # usually static sensors, tweak as desired
        ra6 = false; # generally no SLAAC unless you want it
        routable = true;
        transit = false;
        dns = true;
        reverseDns = true;
        mtu = 1500;
      };
    }

    {
      key = "access-transit";
      range = {
        from = 100;
        to = 199;
      };
      plane = "transit";
      trust = "neutral";
      role = "router-links";
      defaults = {
        kind = "lan";
        dhcp4 = false;
        ra6 = false;
        routable = true;
        transit = true;
        dns = false;
        reverseDns = false;
        mtu = 1500;
        ipv4PrefixLen = 31;
        ipv6PrefixLen = 127;
      };
    }
    {
      key = "core-transit";
      range = {
        from = 200;
        to = 299;
      };
      plane = "transit";
      trust = "neutral";
      role = "router-links";
      defaults = {
        kind = "lan";
        dhcp4 = false;
        ra6 = false;
        routable = true;
        transit = true;
        dns = false;
        reverseDns = false;
        mtu = 1500;
        ipv4PrefixLen = 31;
        ipv6PrefixLen = 127;
      };
    }

    {
      key = "legacy-upstream";
      range = {
        from = 1000;
        to = 4094;
      };
      plane = "upstream";
      trust = "unknown";
      role = "wan-handoff";
      defaults = {
        kind = "wan";
        acceptRA = true;
        routable = true;
        mtu = 1500;
      };
    }
  ];

  getFabric =
    vid:
    let
      matches = lib.filter (f: inRange f.range vid) fabrics;
    in
    if matches == [ ] then null else lib.head matches;

in
{
  inherit fabrics inRange;

  fabricForVlan =
    vid:
    let
      f = getFabric vid;
    in
    if f == null then throw "fabrics: VLAN ${toString vid} not in any defined range" else f;

  fabricKeyForVlan =
    vid:
    let
      f = getFabric vid;
    in
    if f == null then throw "fabrics: VLAN ${toString vid} not in any defined range" else f.key;

  applyDefaults =
    vid: attrs:
    let
      f = getFabric vid;
    in
    if f == null then
      attrs
    else
      f.defaults
      // attrs
      // {
        fabric = f.key;
        plane = f.plane;
        trust = f.trust;
      };
}
