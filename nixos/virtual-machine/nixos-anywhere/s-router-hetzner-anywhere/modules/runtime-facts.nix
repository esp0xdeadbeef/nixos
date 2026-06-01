{ runtime }:
let
  require = name: value:
    if value == null || value == "" || value == [ ] then
      throw "s-router-hetzner-anywhere: runtime.nix must set ${name} before deployment"
    else
      value;
  runtimeSecretsDir = "/persist/s-router-test-runtime";
in
{
  inherit runtimeSecretsDir require;
  publicIPv4Gateway = require "publicIPv4Gateway" (runtime.publicIPv4Gateway or null);
  primaryInterfaceMac = require "primaryInterfaceMac" (runtime.primaryInterfaceMac or null);
  primaryInterfaceFallback = require "primaryInterface" (runtime.primaryInterface or null);
  rootPasswordHashPath = "${runtimeSecretsDir}/hetzner-root-password-hash";
  publicIPv4SecretPath = "${runtimeSecretsDir}/hetzner-public-ipv4";
  lighthousePublicIPv4SecretPath = "${runtimeSecretsDir}/hetzner-lighthouse-public-ipv4";
  publicIPv6SecretPath = "${runtimeSecretsDir}/hetzner-public-ipv6";
  publicIPv6AddressSecretPath = "${runtimeSecretsDir}/hetzner-public-ipv6-address";
  routedIPv6PrefixesSecretPath = "${runtimeSecretsDir}/hetzner-routed-ipv6-prefixes";
}
