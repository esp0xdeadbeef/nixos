{
  lib,
  renderedContainers ? { },
  hetznerAccessPrefixSecretNames ? [ ],
}:
let
  secretMounts =
    lib.genAttrs
      (builtins.map (secretName: "/run/secrets/${secretName}") hetznerAccessPrefixSecretNames)
      (secretPath: {
        hostPath = secretPath;
        isReadOnly = true;
      });
in
lib.mapAttrs
  (_containerName: container:
    container
    // {
      bindMounts =
        (if builtins.isAttrs (container.bindMounts or null) then
          container.bindMounts
        else
          { })
        // secretMounts;
    })
  renderedContainers
