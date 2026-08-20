# Site-a vlan2 static client reservations (per-device protected identities).
# Handle == secret filename under secrets/devices/<handle>.age; offset is
# the host octet within 192.168.1.0/24.
{
  codex-jail = {
    hostname = "codex-jail";
    scopes = {
      vlan2 = 85;
    };
  };
  cs-10 = {
    hostname = "cs-10";
    scopes = {
      vlan2 = 8;
    };
  };
  cs-20 = {
    hostname = "cs-20";
    scopes = {
      vlan2 = 9;
    };
  };
  deadbeef-dock = {
    hostname = "deadbeef-dock";
    scopes = {
      vlan2 = 90;
    };
  };
  deadbeef-wifi = {
    hostname = "deadbeef-wifi";
    scopes = {
      vlan2 = 91;
    };
  };
  house-unifi = {
    hostname = "house-unifi";
    scopes = {
      vlan2 = 52;
    };
  };
  house-unifi-55 = {
    hostname = "house-unifi-55";
    scopes = {
      vlan2 = 55;
    };
  };
  idrac-201 = {
    hostname = "idrac-201";
    scopes = {
      vlan2 = 201;
    };
  };
  idrac-202 = {
    hostname = "idrac-202";
    scopes = {
      vlan2 = 202;
    };
  };
  idrac-203 = {
    hostname = "idrac-203";
    scopes = {
      vlan2 = 203;
    };
  };
  idrac-204 = {
    hostname = "idrac-204";
    scopes = {
      vlan2 = 204;
    };
  };
  idrac-205 = {
    hostname = "idrac-205";
    scopes = {
      vlan2 = 205;
    };
  };
  inverter-office = {
    hostname = "inverter-office";
    scopes = {
      vlan2 = 23;
    };
  };
  inverter-stone-shed = {
    hostname = "inverter-stone-shed";
    scopes = {
      vlan2 = 22;
    };
  };
  l-esp = {
    hostname = "l-esp";
    scopes = {
      vlan2 = 87;
    };
  };
  l-portal = {
    hostname = "l-portal";
    scopes = {
      vlan2 = 88;
    };
  };
  netgear-green-shed = {
    hostname = "netgear-green-shed";
    scopes = {
      vlan2 = 211;
    };
  };
  netgear-house = {
    hostname = "netgear-house";
    scopes = {
      vlan2 = 210;
    };
  };
  office-unifi = {
    hostname = "office-unifi";
    scopes = {
      vlan2 = 54;
    };
  };
  phone-mob = {
    hostname = "phone-mob";
    scopes = {
      vlan2 = 20;
    };
  };
  phone-private = {
    hostname = "phone-private";
    scopes = {
      vlan2 = 21;
    };
  };
  printer-office = {
    hostname = "printer-office";
    scopes = {
      vlan2 = 80;
    };
  };
  printer-office-backup = {
    hostname = "printer-office-backup";
    scopes = {
      vlan2 = 81;
    };
  };
  pve-backup = {
    hostname = "pve-backup";
    scopes = {
      vlan2 = 72;
    };
  };
  pve-prod = {
    hostname = "pve-prod";
    scopes = {
      vlan2 = 70;
    };
  };
  qnap-backup = {
    hostname = "qnap-backup";
    scopes = {
      vlan2 = 76;
    };
  };
  qnap-core-nas = {
    hostname = "qnap-core-nas";
    scopes = {
      vlan2 = 75;
    };
  };
  s-agents = {
    hostname = "s-agents";
    scopes = {
      vlan2 = 86;
    };
  };
  s-nebula = {
    hostname = "s-nebula";
    scopes = {
      vlan2 = 6;
    };
  };
  s-nebula-container = {
    hostname = "s-nebula-container";
    scopes = {
      vlan3 = 10;
    };
  };
  s-llm-inference-container = {
    hostname = "s-llm-inference-container";
    scopes = {
      vlan3 = 11;
    };
  };
  s-router-access = {
    hostname = "s-router-access";
    scopes = {
      vlan2 = 16;
    };
  };
  s-router-clab = {
    hostname = "s-router-clab";
    scopes = {
      vlan2 = 19;
    };
  };
  s-router-core = {
    hostname = "s-router-core";
    scopes = {
      vlan2 = 4;
    };
  };
  s-router-nixos = {
    hostname = "s-router-nixos";
    scopes = {
      vlan2 = 17;
    };
  };
  s-router-policy-only = {
    hostname = "s-router-policy-only";
    scopes = {
      vlan2 = 2;
    };
  };
  s-router-prod = {
    hostname = "s-router-prod";
    scopes = {
      vlan2 = 24;
    };
  };
  s-router-test-clients = {
    hostname = "s-router-test-clients";
    scopes = {
      vlan2 = 18;
    };
  };
  s-router-vpn-egress = {
    hostname = "s-router-vpn-egress";
    scopes = {
      vlan2 = 3;
    };
  };
  s-sigma = {
    hostname = "s-sigma";
    scopes = {
      vlan2 = 98;
    };
  };
  s-sigma-idrac = {
    hostname = "s-sigma-idrac";
    scopes = {
      vlan2 = 206;
    };
  };
  s-tau = {
    hostname = "s-tau";
    scopes = {
      vlan2 = 99;
    };
  };
  s-tau-idrac = {
    hostname = "s-tau-idrac";
    scopes = {
      vlan2 = 200;
    };
  };
  s-test = {
    hostname = "s-test";
    scopes = {
      vlan2 = 5;
    };
  };
  shed-green-unifi = {
    hostname = "shed-green-unifi";
    scopes = {
      vlan2 = 53;
    };
  };
  shed-stone-unifi = {
    hostname = "shed-stone-unifi";
    scopes = {
      vlan2 = 51;
    };
  };
  ubuntu-latest = {
    hostname = "ubuntu-latest";
    scopes = {
      vlan2 = 176;
    };
  };
  unifi-server = {
    hostname = "unifi-server";
    scopes = {
      vlan2 = 50;
    };
  };
  win-pc-14 = {
    hostname = "win-pc-14";
    scopes = {
      vlan2 = 14;
    };
  };
  win-pc-15 = {
    hostname = "win-pc-15";
    scopes = {
      vlan2 = 15;
    };
  };
}
