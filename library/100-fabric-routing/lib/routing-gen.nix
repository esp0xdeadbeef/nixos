# lib/routing-gen.nix
{ lib, ulaPrefix, tenantV4Base }:

topoResolved:

let
  step1 = import ./routing/tenant-lan.nix {
    inherit lib ulaPrefix;
  } topoResolved;

  step2 = import ./routing/policy-access.nix {
    inherit lib ulaPrefix tenantV4Base;
  } step1;

  step3 = import ./routing/policy-core.nix {
    inherit lib ulaPrefix tenantV4Base;
  } step2;

in
step3



