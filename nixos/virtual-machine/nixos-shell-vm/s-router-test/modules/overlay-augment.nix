{
  lib,
  renderedContainers,
  mkNebulaRuntimeAddon,
  mkNebulaNode,
  mkNebulaProfileMount,
  profileForName,
}:

let
  toPort = value:
    if builtins.isInt value then
      value
    else
      builtins.fromJSON (builtins.toString value);

  nebulaListenPortFor = nodeName: nodeSpec:
    if (nodeSpec.lighthouse.node or null) == nodeName then
      toPort (nodeSpec.lighthouse.port or 4242)
    else
      4242;

  nebulaFirewallModuleFor = nodeName: nodeSpec: profileSpec:
    lib.recursiveUpdate (profileSpec.firewallModule or { }) {
      networking.firewall.allowedTCPPorts = [ (nebulaListenPortFor nodeName nodeSpec) ];
      networking.firewall.allowedUDPPorts = [ (nebulaListenPortFor nodeName nodeSpec) ];
    };

  mkOverlayContainer = nodeName: nodeSpec:
    let
      containerSpec = nodeSpec.materialization.container or (throw "nebulaRuntimePlan.nodes.${nodeName}.materialization.container is required");
      profileSpec = profileForName (containerSpec.profile or (throw "overlayRuntimeNodes.${nodeName}.container.profile is required")) nodeSpec;
    in
    {
      autoStart = true;
      privateNetwork = true;
      enableTun = true;
      hostBridge = containerSpec.hostBridge or (throw "overlayRuntimeNodes.${nodeName}.container.hostBridge is required");
      bindMounts = mkNebulaProfileMount nodeName;

      config = mkNebulaNode {
        inherit nodeName;
        networkModule = profileSpec.networkModule;
        firewallModule = nebulaFirewallModuleFor nodeName nodeSpec profileSpec;
        extraModules = profileSpec.extraModules or [ ];
      };
    };

  mkOverlayAugment = nodeName: nodeSpec:
    let
      containerSpec = nodeSpec.materialization.container or (throw "nebulaRuntimePlan.nodes.${nodeName}.materialization.container is required");
      profileSpec = profileForName (containerSpec.profile or (throw "overlayRuntimeNodes.${nodeName}.container.profile is required")) nodeSpec;
      targetContainer = containerSpec.targetContainer or null;
      baseContainer =
        if builtins.isString targetContainer && builtins.hasAttr targetContainer renderedContainers then
          renderedContainers.${targetContainer}
        else
          { };
      baseConfig =
        if builtins.isAttrs baseContainer && builtins.hasAttr "config" baseContainer then
          baseContainer.config
        else
          { };
    in
    if builtins.isString targetContainer && targetContainer != "" then
      {
        ${targetContainer} = {
          enableTun = true;
          bindMounts = mkNebulaProfileMount nodeName;
          config = { ... }: {
            imports = [
              baseConfig
              (mkNebulaRuntimeAddon {
                inherit nodeName;
                firewallModule = nebulaFirewallModuleFor nodeName nodeSpec profileSpec;
                extraModules = profileSpec.extraModules or [ ];
              })
            ];
          };
        };
      }
    else
      {
        ${nodeName} = mkOverlayContainer nodeName nodeSpec;
      };
in
{
  inherit mkOverlayAugment;
}
