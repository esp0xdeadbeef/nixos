let
  inventory = import ./inventory.nix;
  controlPlane = inventory.controlPlane or { };
in
inventory
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
