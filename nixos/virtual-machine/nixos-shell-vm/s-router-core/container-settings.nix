{
  config,
  pkgs,
  lib,
  fabricCompiled,
  ...
}:

let
  hostname = config.networking.hostName;

  siteKey = lib.findFirst (site: builtins.hasAttr hostname fabricCompiled.${site}.nodes) (throw ''
    container-settings:

    Host '${hostname}' does not exist in compiled fabric.

    Available sites:
    ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames fabricCompiled)}
  '') (builtins.attrNames fabricCompiled);

  site = fabricCompiled.${siteKey};

  node =
    if site.nodes ? ${hostname} then
      site.nodes.${hostname}
    else
      throw ''
        container-settings:

        Node '${hostname}' missing inside site '${siteKey}'
      '';

  isBoxAttr =
    name: v:
    builtins.isAttrs v
    && !(lib.elem name [
      "role"
      "networks"
      "interfaces"
    ]);

  boxes = builtins.attrNames (lib.filterAttrs isBoxAttr node);

  mkContainer =
    boxName:
    let
      fabricNodeContext = node.${boxName};
      containerPath = ./. + "/container-${boxName}";
      cname = boxName;
    in
    {
      name = "${hostname}-${boxName}";
      value = {
        autoStart = true;
        privateNetwork = true;

        extraVeths = {
          "${cname}-wan" = {
            hostBridge = "br-upstream";
          };
          "${cname}-lan" = {
            hostBridge = "br-fabric";
          };
        };

        specialArgs = {
          inherit fabricNodeContext;
          containerName = cname;
        };

        additionalCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
        ];

        config = containerPath;
      };
    };

  containersGenerated = builtins.listToAttrs (map mkContainer boxes);

in
{
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  containers = containersGenerated;
}
