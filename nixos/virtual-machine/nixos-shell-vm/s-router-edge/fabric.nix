# fabrics.nix
{ lib, ... }:

let
  #
  # Helper: generate inclusive VLAN list from range
  #
  genVlanList = { from, to }:
    builtins.genList (i: from + i) (to - from + 1);
in
{
  fabrics = {
    control = {
      vlanRange = { from = 10; to = 19; };
      vlans = genVlanList { from = 10; to = 19; };

      plane = "control";
      trust = "absolute";

      defaults = {
        ra6 = false;
        dhcp4 = false;
        routable = true;
        transit = false;
      };
    };

    service = {
      vlanRange = { from = 20; to = 29; };
      vlans = genVlanList { from = 20; to = 29; };

      plane = "service";
      trust = "limited";

      defaults = {
        ra6 = true;
        dhcp4 = true;
        routable = true;
        transit = false;
      };
    };

    endpoint = {
      vlanRange = { from = 30; to = 39; };
      vlans = genVlanList { from = 30; to = 39; };

      plane = "endpoint";
      trust = "untrusted";

      defaults = {
        ra6 = true;
        dhcp4 = true;
        routable = true;
        transit = false;
      };
    };

    iot = {
      vlanRange = { from = 50; to = 59; };
      vlans = genVlanList { from = 50; to = 59; };

      plane = "iot";
      trust = "hostile";

      defaults = {
        ra6 = true;
        dhcp4 = true;
        routable = true;
        transit = false;
      };
    };

    dmz = {
      vlanRange = { from = 60; to = 69; };
      vlans = genVlanList { from = 60; to = 69; };

      plane = "dmz";
      trust = "exposed";

      defaults = {
        ra6 = false;
        dhcp4 = false;
        routable = true;
        transit = false;
      };
    };

    lab = {
      vlanRange = { from = 70; to = 79; };
      vlans = genVlanList { from = 70; to = 79; };

      plane = "lab";
      trust = "actively-hostile";

      defaults = {
        ra6 = true;
        dhcp4 = true;
        routable = true;
        transit = false;
      };
    };

    observability = {
      vlanRange = { from = 80; to = 89; };
      vlans = genVlanList { from = 80; to = 89; };

      plane = "observability";
      trust = "limited";

      defaults = {
        ra6 = false;
        dhcp4 = false;
        routable = true;
        transit = false;
      };
    };

    transit = {
      vlanRange = { from = 100; to = 199; };
      vlans = genVlanList { from = 100; to = 199; };

      plane = "transit";
      trust = "neutral";

      defaults = {
        ra6 = false;
        dhcp4 = false;
        routable = true;
        transit = true;
      };

      constraints = {
        ipv4Prefix = 31;
        ipv6Prefix = 127;
      };
    };

    upstream = {
      vlanRange = { from = 1000; to = 4094; };
      vlans = genVlanList { from = 1000; to = 4094; };

      plane = "upstream";
      trust = "unknown";

      defaults = {
        ra6 = false;
        dhcp4 = false;
        routable = false;
        transit = false;
      };
    };
  };
}

