{
  config,
  pkgs,
  lib,
  fabricCompiled,
  ...
}:

let
  hostname = config.networking.hostName;

  # --------------------------------------------------
  # Find which site this machine belongs to
  # --------------------------------------------------
  siteKey =
    lib.findFirst
      (site:
        builtins.hasAttr hostname fabricCompiled.${site}.nodes
      )
      (throw ''
        container-settings:

        Host '${hostname}' does not exist in compiled fabric.

        Available sites:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames fabricCompiled)}
      '')
      (builtins.attrNames fabricCompiled);

  site = fabricCompiled.${siteKey};

  # --------------------------------------------------
  # Extract THIS node from compiled topology
  # --------------------------------------------------
  node =
    if site.nodes ? ${hostname} then
      site.nodes.${hostname}
    else
      throw ''
        container-settings:

        Node '${hostname}' missing inside site '${siteKey}'
      '';

  # --------------------------------------------------
  # execution contexts (boxes)
  # --------------------------------------------------
  isBoxAttr =
    name: v:
    builtins.isAttrs v && !(lib.elem name [
      "role"
      "networks"
      "interfaces"
    ]);

  boxes = builtins.attrNames (lib.filterAttrs isBoxAttr node);

  # --------------------------------------------------
  # create one container per box
  # --------------------------------------------------
  mkContainer =
    boxName:
    let
      fabricNodeContext = node.${boxName};
      containerPath = ./. + "/container-${boxName}";
    in
    {
      name = "${hostname}-${boxName}";
      value = {
        autoStart = true;
        privateNetwork = true;

        # host bridges trunked into router
        extraVeths = {
          wan.hostBridge = "br-upstream";
          lan.hostBridge = "br-fabric";
        };

        specialArgs = {
          inherit fabricNodeContext;
        };

        additionalCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
        ];

        config = containerPath;
      };
    };

  containersGenerated =
    builtins.listToAttrs (map mkContainer boxes);

in
{
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  containers = containersGenerated;
}
