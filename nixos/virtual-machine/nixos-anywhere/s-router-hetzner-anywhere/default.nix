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
  hetznerHostNetworks = builtins.removeAttrs renderedHostNetworks [ "20-eth0" "30-br-wan" ];
  internalWanPrefix = "172.31.254";
  internalWanAddress = "${internalWanPrefix}.1/24";
  internalWanForwardTarget = "${internalWanPrefix}.2";
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
      systemd.network.netdevs = renderedNetdevs;
      systemd.network.networks = lib.recursiveUpdate
        (hetznerHostNetworks // {
          "20-hetzner-public" = {
            matchConfig = primaryInterfaceMatchConfig;
            linkConfig = {
              ActivationPolicy = "always-up";
              RequiredForOnline = "routable";
            };
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
        })
        {
          "30-br-wan" = {
            networkConfig = {
              DHCP = "no";
              DHCPServer = true;
              IPv4Forwarding = true;
              IPv6AcceptRA = false;
            };
            address = [ internalWanAddress ];
            dhcpServerConfig = {
              PoolOffset = 2;
              PoolSize = 32;
              EmitDNS = true;
              DNS = [ "1.1.1.1" "9.9.9.9" ];
            };
          };
        };
      boot.kernel.sysctl."net.ipv4.ip_forward" = lib.mkForce true;
      systemd.services.hetzner-wan-nat = {
        description = "SNAT br-wan and forward non-SSH public traffic";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [
          pkgsForRenderer.coreutils
          pkgsForRenderer.gnused
          pkgsForRenderer.iproute2
          pkgsForRenderer.iptables
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          wan_if="$(ip -o -4 route show default | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -n 1)"
          if [ -z "$wan_if" ]; then
            echo "could not determine public WAN interface" >&2
            exit 1
          fi

          iptables -t nat -C POSTROUTING -s ${internalWanPrefix}.0/24 -o "$wan_if" -j MASQUERADE 2>/dev/null \
            || iptables -t nat -A POSTROUTING -s ${internalWanPrefix}.0/24 -o "$wan_if" -j MASQUERADE
          iptables -C FORWARD -i br-wan -o "$wan_if" -j ACCEPT 2>/dev/null \
            || iptables -A FORWARD -i br-wan -o "$wan_if" -j ACCEPT
          iptables -C FORWARD -i "$wan_if" -o br-wan -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
            || iptables -A FORWARD -i "$wan_if" -o br-wan -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
          iptables -t nat -C PREROUTING -i "$wan_if" -p tcp ! --dport 22 -j DNAT --to-destination ${internalWanForwardTarget} 2>/dev/null \
            || iptables -t nat -A PREROUTING -i "$wan_if" -p tcp ! --dport 22 -j DNAT --to-destination ${internalWanForwardTarget}
          iptables -t nat -C PREROUTING -i "$wan_if" -p udp -j DNAT --to-destination ${internalWanForwardTarget} 2>/dev/null \
            || iptables -t nat -A PREROUTING -i "$wan_if" -p udp -j DNAT --to-destination ${internalWanForwardTarget}
        '';
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
