# /home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-access/container-router-access/dns.nix
# FILE: container-router-access/dns.nix
{
  config,
  pkgs,
  lib,
  vlanId,
  outPath,
  ...
}:

let
  fabric = import "${outPath}/library/100-fabric-routing/inputs";
  v4Base = fabric.tenantV4Base or "10.10";
  ulaPrefix = fabric.ulaPrefix or "fd42:dead:beef";

  site = import "${outPath}/library/100-fabric-routing/lib/site-defaults.nix";

  domainRaw = site.domain or "lan.";
  domain = if lib.hasSuffix "." domainRaw then domainRaw else "${domainRaw}.";

  lanIf = "lan-${toString vlanId}";

  lan4 = "${v4Base}.${toString vlanId}.1";
  lan6 = "${ulaPrefix}:${toString vlanId}::1";

  v4Net = "${v4Base}.${toString vlanId}.0/24";
  v6Net = "${ulaPrefix}:${toString vlanId}::/64";

  upstream = site.defaultWanDns or [
    "1.1.1.1"
    "9.9.9.9"
    "2606:4700:4700::1111"
    "2606:4700:4700::1001"
  ];
in
{
  services.bind.enable = lib.mkForce false;

  services.unbound = {
    enable = true;

    settings.server = {
      interface = [
        lan4
        lan6
        "127.0.0.1"
        "::1"
      ];

      outgoing-interface = [
        lan4
        lan6
      ];

      port = 53;
      do-ip4 = true;
      do-ip6 = true;
      do-udp = true;
      do-tcp = true;

      access-control = [
        "127.0.0.0/8 allow"
        "::1 allow"
        "${v4Net} allow"
        "${v6Net} allow"
      ];

      local-zone = [ "${domain} static" ];

      auto-trust-anchor-file = "/var/lib/unbound/root.key";
      hide-identity = true;
      hide-version = true;
      harden-glue = true;
      harden-dnssec-stripped = true;
      qname-minimisation = true;

      prefetch = true;
      cache-min-ttl = 60;
      cache-max-ttl = 86400;
    };

    settings.forward-zone = [
      {
        name = ".";
        forward-addr = upstream;
        forward-first = true;
      }
    ];
  };

  networking.nameservers = [
    "127.0.0.1"
    "::1"
  ];
}

