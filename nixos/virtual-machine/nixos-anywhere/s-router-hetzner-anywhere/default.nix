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
      systemd.network.netdevs = (renderedHost.netdevs or { }) // (renderedBridges.netdevs or { });
      systemd.network.networks = lib.recursiveUpdate
        ((renderedHost.networks or { }) // (renderedBridges.networks or { }))
        {
          "30-br-wan" = {
            networkConfig = {
              DHCP = "ipv4";
              IPv6AcceptRA = false;
            };
            address = [
              (require "publicIPv6Address" runtime.publicIPv6Address)
            ] ++ map floatingIPv6HostAddress runtime.floatingIPv6Prefixes;
            routes = [
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
