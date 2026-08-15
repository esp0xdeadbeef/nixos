# Combined multi-site inventory used by every router renderer.
#
# `intent.nix` is shared and unfiltered, so each renderer compiles every site
# against this combined inventory. The renderer then selects only the nodes
# whose `host` matches the rendered host name.
let
  neon = import ./inventory-neon.nix;
  cobalt = import ./inventory-cobalt.nix;
in
{
  schemaVersion = 1;
  endpoints = neon.endpoints // cobalt.endpoints;
  deployment.hosts = neon.deployment.hosts // cobalt.deployment.hosts;
  realization = {
    fabricLinks = (neon.realization.fabricLinks or { }) // (cobalt.realization.fabricLinks or { });
    nodes = neon.realization.nodes // cobalt.realization.nodes;
  };
  # Site-a still carries a legacy role-keyed render.hosts section. The current
  # renderer looks render.hosts up by host name and falls back to
  # deployment.hosts.<host>.wanUplink, so this is harmless and cobalt does not
  # need an equivalent section.
  render.hosts = neon.render.hosts or { };
  secrets = neon.secrets or { };
  controlPlane.sites = (neon.controlPlane.sites or { }) // (cobalt.controlPlane.sites or { });
}
