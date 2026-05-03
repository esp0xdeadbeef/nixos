{ lib, hetznerAccessPrefixSecretNames ? [ ], ... }:

let
  mkRootSecret = _name: {
    owner = "root";
    mode = "0400";
  };
in
{
  sops.secrets =
    {
      pppoe-username = mkRootSecret "pppoe-username";
      pppoe-password = mkRootSecret "pppoe-password";
      hetzner-public-ipv4 = mkRootSecret "hetzner-public-ipv4";
      hetzner-public-ipv6 = mkRootSecret "hetzner-public-ipv6";
      hetzner-primary-interface-mac = mkRootSecret "hetzner-primary-interface-mac";
    }
    // lib.genAttrs hetznerAccessPrefixSecretNames mkRootSecret;
}
