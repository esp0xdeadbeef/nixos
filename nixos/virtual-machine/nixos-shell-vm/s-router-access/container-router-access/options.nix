{ lib, ... }:

{
  options.routerAccess = {
    tenantVlans = lib.mkOption {
      type = lib.types.listOf lib.types.int;
      description = "Tenant VLAN IDs served by router-access";
      default = [ ];
    };

    policyAccessTransitBase = lib.mkOption {
      type = lib.types.int;
      description = "Base VLAN ID for policy↔access transit links";
      default = 100;
    };
  };
}
