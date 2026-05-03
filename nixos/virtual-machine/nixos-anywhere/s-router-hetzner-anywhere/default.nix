{ inputs
, lib
, ...
}:
let
  nixosRenderer = inputs.network-renderer-nixos.lib;
  runtime = import ./runtime.nix;
  system = "x86_64-linux";
  pkgsForRenderer = inputs.nixpkgs.legacyPackages.${system};
  nebulaRenderer = inputs.network-renderer-nebula.libBySystem.${system}.renderer;
  fabric = {
    intentPath = "${inputs.network-labs}/examples/s-router-test-three-site/intent.nix";
    inventoryPath = "${inputs.network-labs}/examples/s-router-test-three-site/inventory-nixos.nix";
  };
  builtHost = nixosRenderer.renderer.buildHostFromPaths {
    inherit (fabric) intentPath inventoryPath;
    selector = "s-router-hetzner-anywhere";
    file = "nixos/virtual-machine/nixos-anywhere/s-router-hetzner-anywhere/default.nix";
  };
  renderedHost = nixosRenderer.host.build {
    inherit (fabric) intentPath inventoryPath;
    boxName = "s-router-hetzner-anywhere";
  };
  renderedBridges = nixosRenderer.bridges.build {
    inherit (fabric) intentPath inventoryPath;
    boxName = "s-router-hetzner-anywhere";
  };
  renderedContainers = nixosRenderer.containers.buildForBox {
    inherit (fabric) intentPath inventoryPath;
    boxName = "s-router-hetzner-anywhere";
    defaults = {
      autoStart = true;
      additionalCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];
    };
  };
  nebulaRuntimePlan = nebulaRenderer.buildNebulaPlan {
    controlPlane = builtHost.controlPlaneOut or { };
    inventory = builtHost.globalInventory or { };
  };
  externalLighthouseModule = nebulaRenderer.buildExternalLighthouseNixosModule {
    pkgs = pkgsForRenderer;
    inherit nebulaRuntimePlan;
  };
  require = name: value:
    if value == null || value == "" || value == [ ] then
      throw "s-router-hetzner-anywhere: runtime.nix must set ${name} before deployment"
    else
      value;
  floatingIPv6HostAddress =
    prefix:
    if lib.hasSuffix "::/64" prefix then
      "${lib.removeSuffix "::/64" prefix}::1/128"
    else
      throw "s-router-hetzner-anywhere: floating IPv6 prefix must be canonical ::/64: ${prefix}";
  publicIPv4Address = "${require "publicIPv4" runtime.publicIPv4}/32";
  publicIPv4Gateway = require "publicIPv4Gateway" (runtime.publicIPv4Gateway or null);
  primaryInterfaceMac = require "primaryInterfaceMac" (runtime.primaryInterfaceMac or null);
  primaryInterfaceMatchConfig =
    {
      Name =
        if builtins.isString (runtime.primaryInterfaceMatch or null) && runtime.primaryInterfaceMatch != "" then
          runtime.primaryInterfaceMatch
        else
          "en* eth*";
    };
  renderedHostNetworks =
    lib.mapAttrs
      (_: network: builtins.removeAttrs network [ "dhcpConfig" ])
      ((renderedHost.networks or { }) // (renderedBridges.networks or { }));
  renderedNetdevs =
    (renderedHost.netdevs or { }) // (renderedBridges.netdevs or { });
  hetznerNetdevs =
    lib.mapAttrs
      (_: netdev:
        if (netdev.netdevConfig.Name or null) == "br-wan" then
          lib.recursiveUpdate netdev {
            netdevConfig.MACAddress = primaryInterfaceMac;
          }
        else
          netdev)
      renderedNetdevs;
  hetznerHostNetworks = builtins.removeAttrs renderedHostNetworks [ "20-eth0" "30-br-wan" ];
in
{
  imports = [
    inputs.disko.nixosModules.disko
    (builtHost.artifactModule or { })
    ./disko.nix
    ./hardware.nix
  ];

  config = lib.mkMerge [
    externalLighthouseModule
    {

      assertions = [
        {
          assertion = runtime.publicIPv4 != null;
          message = "runtime.nix must be generated from the Hetzner spawn output";
        }
      ];

      networking.hostName = "hetzner-nebula-prodtest-01";
      networking.useDHCP = false;
      systemd.network.enable = true;
      systemd.network.netdevs = hetznerNetdevs;
      systemd.network.networks = lib.recursiveUpdate
        (hetznerHostNetworks // {
          "20-hetzner-wan-parent" =
            (builtins.removeAttrs (renderedHostNetworks."20-eth0" or { }) [ "dhcpConfig" ])
            // {
              matchConfig = primaryInterfaceMatchConfig;
              networkConfig = (renderedHostNetworks."20-eth0".networkConfig or { }) // {
                Bridge = "br-wan";
              };
            };
        })
        {
          "30-br-wan" = {
            networkConfig = {
              DHCP = "no";
              IPv6AcceptRA = false;
            };
            address = [
              publicIPv4Address
              (require "publicIPv6Address" runtime.publicIPv6Address)
            ] ++ map floatingIPv6HostAddress runtime.floatingIPv6Prefixes;
            routes = [
              {
                Destination = "${publicIPv4Gateway}/32";
                Scope = "link";
              }
              { Gateway = publicIPv4Gateway; }
              { Gateway = "fe80::1"; }
            ];
          };
        };

      boot.loader.grub = {
        enable = true;
        device = "/dev/sda";
        efiSupport = true;
        efiInstallAsRemovable = true;
      };
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      users.users.root.openssh.authorizedKeys.keys =
        require "authorizedKeys" runtime.authorizedKeys;

      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "prohibit-password";
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
        };
      };

      networking.firewall.allowedTCPPorts = [ 22 ];
      networking.firewall.checkReversePath = lib.mkForce false;

      environment.etc."s-router-test/hetzner-runtime.json".text = builtins.toJSON runtime;
      environment.etc."network-renderer/network-renderer-nebula.json".text = builtins.toJSON {
        overlays = builtins.attrNames (nebulaRuntimePlan.overlays or { });
        nodes = builtins.attrNames (nebulaRuntimePlan.nodes or { });
      };

      containers = renderedContainers;

      system.stateVersion = "25.11";
    }
  ];
}
