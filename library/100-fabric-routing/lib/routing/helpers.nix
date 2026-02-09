# lib/routing/helpers.nix
{
  lib,
  ulaPrefix,
  tenantV4Base,
}:

let
  tenant4Dst = vid: "${tenantV4Base}.${toString vid}.0/24";
  tenant6DstUla = vid: "${ulaPrefix}:${toString vid}::/64";

  getTenantVid =
    ep:
    if ep ? tenant && builtins.isAttrs ep.tenant && ep.tenant ? vlanId then ep.tenant.vlanId else null;

in
{
  inherit tenant4Dst tenant6DstUla getTenantVid;
}
