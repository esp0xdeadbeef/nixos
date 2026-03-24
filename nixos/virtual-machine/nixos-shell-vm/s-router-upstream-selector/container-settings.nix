{
  config,
  lib,
  controlPlaneOut,
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
    if inventory ? fabric && builtins.isAttrs inventory.fabric then
      inventory.fabric
    else
      throw "container-settings.nix: inventory.fabric missing";

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  unitBelongsToHost =
    unitName:
      unitName == hostname
      || lib.hasPrefix "${hostname}-" unitName;

  inventoryUnitNames = sortedAttrNames fabricInventory;

  selectedUnits =
    let
      matched = lib.filter unitBelongsToHost inventoryUnitNames;
    in
    if matched != [ ] then
      matched
    else
      inventoryUnitNames;

  _selectedNonEmpty =
    if selectedUnits != [ ] then
      true
    else
      throw "container-settings.nix: no units found in inventory.fabric";

  collectNodeMatches =
    unitName: value:
      if builtins.isAttrs value then
        let
          direct =
            if value ? nodes && builtins.isAttrs value.nodes && builtins.hasAttr unitName value.nodes then
              [ value.nodes.${unitName} ]
            else
              [ ];

          nested =
            lib.concatMap
              (name: collectNodeMatches unitName value.${name})
              (lib.filter (name: name != "nodes") (sortedAttrNames value));
        in
        direct ++ nested
      else if builtins.isList value then
        lib.concatMap (x: collectNodeMatches unitName x) value
      else
        [ ];

  mkHostBridge =
    portName: portSpec:
      if portSpec ? vlan then
        "tr${toString portSpec.vlan}"
      else
        throw "container-settings.nix: missing vlan for fabric port '${portName}'";

  mkContainer =
    unitName:
    let
      fabricSpec =
        if builtins.hasAttr unitName fabricInventory then
          fabricInventory.${unitName}
        else
          throw "container-settings.nix: missing fabric inventory for unit '${unitName}'";

      fabricNodeContextMatches = collectNodeMatches unitName controlPlaneOut;

      fabricNodeContext =
        if fabricNodeContextMatches != [ ] then
          builtins.head fabricNodeContextMatches
        else
          throw "container-settings.nix: no control-plane node matched unit '${unitName}'";

      role =
        if fabricNodeContext ? role then
          fabricNodeContext.role
        else
          throw "container-settings.nix: missing role for unit '${unitName}'";

      containerTemplate =
        if role == "upstream-selector" then
          "upstream-selector"
        else
          throw "container-settings.nix: unsupported role '${role}' for unit '${unitName}'";

      portNames =
        if fabricSpec ? ports && builtins.isAttrs fabricSpec.ports then
          sortedAttrNames fabricSpec.ports
        else
          throw "container-settings.nix: missing ports for unit '${unitName}'";

      extraVeths =
        builtins.listToAttrs (
          map
            (
              portName:
              let
                portSpec = fabricSpec.ports.${portName};
              in
              {
                name = portName;
                value = {
                  hostBridge = mkHostBridge portName portSpec;
                };
              }
            )
            portNames
        );
    in
    {
      name = unitName;
      value = {
        autoStart = true;

        privateNetwork = true;
        hostBridge = null;

        inherit extraVeths;

        specialArgs = {
          inherit controlPlaneOut fabricSpec fabricNodeContext;
        };

        additionalCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
        ];

        config = { controlPlaneOut, fabricSpec, fabricNodeContext, ... }: {
          imports = [
            ./container-upstream-selector
          ];

          _module.args = {
            inherit controlPlaneOut fabricSpec fabricNodeContext;
          };

          networking.hostName = unitName;
        };
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
