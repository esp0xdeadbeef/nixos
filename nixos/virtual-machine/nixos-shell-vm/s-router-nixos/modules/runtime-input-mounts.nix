{
  lib,
  renderedContainers ? { },
}:

let
  runtimeInputMounts = {
    "/etc/network-artifacts" = {
      hostPath = "/etc/static/network-artifacts";
      isReadOnly = true;
    };
    "/persist/nebula-runtime" = {
      hostPath = "/persist/nebula-runtime";
      isReadOnly = false;
    };
  };
in
lib.mapAttrs (
  _containerName: container:
  container
  // {
    enableTun = true;
    bindMounts =
      (if builtins.isAttrs (container.bindMounts or null) then container.bindMounts else { })
      // runtimeInputMounts;
  }
) renderedContainers
