{
  config,
  pkgs,
  lib,
  fabricCompiled,
  ...
}:

let
  hostname = config.networking.hostName;

  inventoryImported = import ./inventory.nix;
  inventory =
    if builtins.isFunction inventoryImported then
      inventoryImported { inherit lib; }
    else
      inventoryImported;

  fabricInventory =
    if inventory ? fabric then inventory.fabric else { };

  enterprises =
    if fabricCompiled ? enterprise && builtins.isAttrs fabricCompiled.enterprise then
      fabricCompiled.enterprise
    else
      throw "fabricCompiled.enterprise missing";

  enterpriseName =
    let names = builtins.attrNames enterprises;
    in
    if builtins.length names == 1 then builtins.head names
    else throw "expected exactly 1 enterprise";

  enterprise = enterprises.${enterpriseName};

  sites =
    if enterprise ? site && builtins.isAttrs enterprise.site then
      enterprise.site
    else
      throw "enterprise.site missing";

  siteName =
    let names = builtins.attrNames sites;
    in
    if builtins.length names == 1 then builtins.head names
    else throw "expected exactly 1 site";

  site = sites.${siteName};

  units =
    if site ? units && builtins.isAttrs site.units then
      site.units
    else
      throw "site.units missing";

  nodes =
    if site ? nodes && builtins.isAttrs site.nodes then
      site.nodes
    else
      throw "site.nodes missing";

  allUnitNames = builtins.attrNames units;

  unitBelongsToHost =
    unitName:
      unitName == hostname
      || lib.hasPrefix "${hostname}-" unitName;

  selectedUnits = lib.filter unitBelongsToHost allUnitNames;

  _selectedNonEmpty =
    if selectedUnits != [ ] then true
    else throw "no units matched host";

  mkContainer =
    unitName:
    let
      fabricNodeContext =
        if builtins.hasAttr unitName nodes then
          nodes.${unitName}
        else
          throw "missing node context";

      role =
        if fabricNodeContext ? role then
          fabricNodeContext.role
        else
          throw "missing role";

      containerTemplate =
        if role == "upstream-selector" then
          "upstream-selector"
        else
          throw "unsupported role";

      containerPath = ./. + "/container-${containerTemplate}";
      containerName = containerTemplate;

      fabricSpec =
        if builtins.hasAttr unitName fabricInventory then
          fabricInventory.${unitName}
        else
          throw "missing fabric inventory for unit";
    in
    {
      name = unitName;
      value = {
        autoStart = true;

        privateNetwork = true;
        hostBridge = null;

        extraVeths = {
          "core" = { hostBridge = "br-upstream"; };
          "policy" = { hostBridge = "br-fabric"; };
        };

        specialArgs = {
          inherit fabricNodeContext containerName fabricSpec;
        };

        additionalCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
        ];

        config = containerPath;
      };
    };

  containersGenerated = builtins.listToAttrs (map mkContainer selectedUnits);

in
{
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  containers = containersGenerated;
}
