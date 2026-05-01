{ inputs
, lib
, ...
}:
let
  runtime = import ./runtime.nix;
  system = "x86_64-linux";
  pkgsForRenderer = inputs.nixpkgs.legacyPackages.${system};
  renderer = inputs.network-renderer-nebula.libBySystem.${system}.renderer;
  plan = renderer.buildNebulaPlanFromPaths {
    intentPath = "${inputs.network-labs}/examples/s-router-test-three-site/intent.nix";
    inventoryPath = "${inputs.network-labs}/examples/s-router-test-three-site/inventory-nixos.nix";
  };
  hetznerNebulaModule = renderer.buildHetznerLighthouseNixosModule {
    pkgs = pkgsForRenderer;
    nebulaRuntimePlan = plan;
    hetznerIpv4NatCidrs = [ "10.70.10.0/24" ];
    externalInterface = runtime.primaryInterface;
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
    ./disko.nix
    ./hardware.nix
  ];

  config = lib.mkMerge [
    hetznerNebulaModule
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
      systemd.network.networks."30-wan" = {
        matchConfig.Name = runtime.primaryInterfaceMatch;
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

      system.stateVersion = "25.11";
    }
  ];
}
