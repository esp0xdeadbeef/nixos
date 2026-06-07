{ inputs
, outPath
, ...
}:
let
  system = "x86_64-linux";
  labSource = "active-lab";
  hostName = "s-router-test-clients";
in
{
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"

    (inputs.network-renderer-access-endpoint-nixos.libBySystem.${system}.renderer.hostModuleFromPaths {
      inherit hostName labSource;

      intentPath = "${inputs.network-labs}/${labSource}/intent.nix";
      inventoryPath = "${inputs.network-labs}/${labSource}/inventory-nixos.nix";
      clientsPath = "${inputs.network-labs}/${labSource}/clients.nix";
      routingSopsPath = "${inputs.network-labs}/${labSource}/sops-routing-${hostName}.nix";
    })

    ./management-vlan2.nix
  ];
}
