{ inputs
, lib
, config
, pkgs
, self
, ...
}:

# Network/infrastructure diagram generation (nix-topology).
#
# This profile wires the nix-topology NixOS module into a host so the host can
# describe its own place in the network (`topology.self`) and so the whole
# diagram can be rendered from the evaluated configuration:
#
#   nix build .#nixosConfigurations.<host>.config.topology.output
#
# That is the ONLY way nix-topology produces anything. It has no runnable app
# (`nix run` has nothing to invoke) and no standalone CLI: the rendered SVG is
# a *build output* of a NixOS configuration that has this module applied. The
# usual `topology.<system>` flake-parts output is not used here -- this repo
# does not depend on flake-parts, and a per-host output is what the hosts that
# import this profile need.
#
# What is automatic and what is not:
#
#   * Interfaces are extracted automatically from `systemd.network.netdevs`
#     and `systemd.network.networks` (the `systemd-network` extractor, on by
#     default). Hosts whose networking is expressed as networkd netdevs --
#     every router VM here, and s-nodus's bridges/VLANs -- therefore get their
#     interface graph without repeating it in `topology.self`.
#   * Services are extracted automatically from the host's NixOS options.
#   * Everything *semantic* is not inferrable and stays host-authored:
#     which uplink reaches the internet, which node terminates a VLAN, where
#     the physical jacks point. Each host supplies that in its own
#     `topology.self` / `local.topology.*` block. Do not try to derive network
#     meaning here -- it is not present in the systemd unit files.
#
# Rendering is independent of the host's own platform: the diagram is built by
# the *evaluating* machine (graphviz/elk over the eval result), so enabling
# this on an aarch64 host does not require an aarch64 builder.
let
  cfg = config.local.topology;
in
{
  imports = [
    inputs.nix-topology.nixosModules.default
  ];

  options.local.topology = {
    enable = lib.mkEnableOption "nix-topology diagram generation for this host";

    # The node id used for this host in the topology graph. Defaults to
    # `networking.hostName`, but a variant host that is the same machine under
    # a different flake attribute (s-nodus-nixos-hardware is s-nodus) must
    # collapse onto the same node, otherwise the diagram gains a phantom device
    # and every connection to the real node dangles. Set it explicitly to the
    # canonical identity in that case.
    id = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = ''
        The node id this host occupies in the topology graph. Defaults to
        `networking.hostName`; override it for a build variant of an existing
        machine so both evaluate to the same node.
      '';
    };

    name = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Human-readable node label. Defaults to the node id.
      '';
    };

    hardwareInfo = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Single line describing the hardware (shown under the node name).";
    };

    output = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      description = ''
        The rendered diagram (a directory holding main.svg and network.svg).
        Built from this host's configuration plus every other host's topology
        data, so cross-host edges are drawn.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Point the host's node at the resolved id and give it a readable name.
    topology.id = lib.mkDefault cfg.id;

    topology.self = {
      name = lib.mkDefault (
        if cfg.name != null then cfg.name else cfg.id
      );
      hardware.info = lib.mkDefault cfg.hardwareInfo;
    };

    # The rendered diagram.
    #
    # The NixOS side of nix-topology only *collects* topology data --
    # `config.topology` holds nodes/interfaces/networks and nothing else; there
    # is no `output` option there (checked: config.topology's attribute names
    # are nodes/networks/self/icons/id/extractors/...). Rendering happens in the
    # separate topology module, which is constructed from a pkgs carrying the
    # nix-topology overlay plus the *complete* `nixosConfigurations` set (it
    # needs every host's topology data to draw cross-host edges).
    #
    # So the build target is exposed here rather than being available on
    # `config.topology.*`: render this host's diagram with
    #   nix build .#nixosConfigurations.<host>.config.local.topology.output
    # The output is a directory containing main.svg and network.svg.
    local.topology.output =
      let
        topologyPkgs = pkgs.extend inputs.nix-topology.overlays.default;

        # Only hosts that actually import the topology module may be handed to
        # the renderer. The topology module walks every configuration it is
        # given and reads `options.topology.nodes.definitions`, so a host
        # without the module aborts the whole evaluation with
        # "cannot find attribute 'options.topology.nodes.definitions'". Pass
        # the annotated subset (a host advertises it by having a
        # `topology.id` option at all), not the whole fleet.
        topologyHosts = lib.filterAttrs (
          _: v: v.config ? topology && v.config.topology ? id
        ) self.nixosConfigurations;
      in
      (import inputs.nix-topology {
        pkgs = topologyPkgs;
        modules = [
          {
            nixosConfigurations = topologyHosts;
          }
        ];
      }).config.output;
  };
}
