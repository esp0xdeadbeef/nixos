# Combined multi-site inventory used by every router renderer.
#
# `intent.nix` is shared and unfiltered, so each renderer compiles every site
# against this combined inventory. The renderer then selects only the nodes
# whose `host` matches the rendered host name.
let
  siteA = import ./inventory.nix;
  cobalt = import ./inventory-cobalt.nix;
in
{
  schemaVersion = 1;
  endpoints = siteA.endpoints // cobalt.endpoints;
  deployment.hosts = siteA.deployment.hosts // cobalt.deployment.hosts;
  realization = {
    fabricLinks = (siteA.realization.fabricLinks or { }) // (cobalt.realization.fabricLinks or { });
    nodes = siteA.realization.nodes // cobalt.realization.nodes;
  };
  # Site-a still carries a legacy role-keyed render.hosts section. The current
  # renderer looks render.hosts up by host name and falls back to
  # deployment.hosts.<host>.wanUplink, so this is harmless and cobalt does not
  # need an equivalent section.
  render.hosts = siteA.render.hosts or { };
  secrets = siteA.secrets or { };
}
