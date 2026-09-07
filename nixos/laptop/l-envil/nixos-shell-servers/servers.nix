{ ... }:
{
  imports = [
    (import ../../../server/nixos-shell-vm-inventory.nix {
      startOnBootInstances = [
        "s-router-cobalt"
        "s-nebula-cobalt"
        "s-tang"
        "s-ap-nighthawk"
        "s-ap-alfa"
      ];
      # The GPU-backed inference VM lives on s-tau; l-envil only runs the
      # local ollama/open-webui stack and does not build this VM image.
      excludeInstances = [ "s-llm-inference" ];
    })
  ];
}
