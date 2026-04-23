let
  bgpInventory = import ./bgp-inventory.nix;
  controlPlane = bgpInventory.controlPlane or { };
in
bgpInventory
// {
  controlPlane =
    controlPlane
    // {
      sites = builtins.mapAttrs (
        _enterprise: sites:
        builtins.mapAttrs (
          _site: site:
          site
          // {
            routing =
              (builtins.removeAttrs (site.routing or { }) [ "bgp" ])
              // {
                mode = "static";
              };
          }
        ) sites
      ) (controlPlane.sites or { });
    };
}
