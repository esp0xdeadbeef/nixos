# lib/site-addressing.nix
{ }:

{
  ula = {
    prefix = "fd42:dead:beef";   # /48 root
  };

  tenant = {
    v4Base = "10.10";            # 10.10.<VID>.0/24
    v4PrefixLen = 24;
    v6PrefixLen = 64;
  };

  transit = {
    v4Base = "10.255";           # 10.255.<TVID>.0/31
    v4PrefixLen = 31;
    v6PrefixLen = 127;
  };

  wan = {
    legacyVlan = 1000;

    v4 = {
      addr = "10.255.255.2/29";
      gw   = "10.255.255.1";
    };

    v6 = {
      addr = "fd42:dead:beef:1000::2/64";
      gw   = "fd42:dead:beef:1000::1";
    };
  };
}

