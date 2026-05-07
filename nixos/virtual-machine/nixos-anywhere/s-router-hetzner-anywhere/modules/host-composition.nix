{ inputs
, lib
, ...
}:
let
  nixosRenderer = inputs.network-renderer-nixos.lib;
  runtime = import ../runtime.nix;
  system = "x86_64-linux";
  pkgsForRenderer = inputs.nixpkgs.legacyPackages.${system};
  nebulaRenderer = inputs.network-renderer-nebula.libBySystem.${system}.renderer;
  labResolvedInventoryPath =
    builtins.toFile "lab-sigma-resolved-inventory-nixos.nix" ''
      import ${inputs.network-labs}/labs/lab-s-sigma/s-router-test-three-site/getResolvedInventory.nix { renderer = "nixos"; }
    '';
  fabric = {
    intentPath = "${inputs.network-labs}/labs/lab-s-sigma/s-router-test-three-site/intent.nix";
    inventoryPath = labResolvedInventoryPath;
  };
  builtHost = nixosRenderer.renderer.buildHostFromPaths {
    inherit (fabric) intentPath inventoryPath;
    selector = "s-router-hetzner-anywhere";
    file = "nixos/virtual-machine/nixos-anywhere/s-router-hetzner-anywhere/default.nix";
  };
  localRouterHost = nixosRenderer.renderer.buildHostFromPaths {
    inherit (fabric) intentPath inventoryPath;
    selector = "s-router-test";
    file = "nixos/virtual-machine/nixos-shell-vm/s-router-test/default.nix";
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
  selectedSiteKeys =
    lib.unique (
      lib.filter
        (key: key != "")
        (
          lib.mapAttrsToList
            (
              _nodeName: node:
              if (node.host or null) == "s-router-hetzner-anywhere" then
                "${node.logicalNode.enterprise or ""}::${node.logicalNode.site or ""}"
              else
                ""
            )
            (((builtHost.globalInventory or { }).realization or { }).nodes or { })
        )
    );
  isSelectedRuntimeNode =
    _nodeName: node:
    builtins.elem "${node.enterpriseName or ""}::${node.siteName or ""}" selectedSiteKeys;
  selectedNebulaRuntimePlan = nebulaRuntimePlan // {
    nodes = lib.filterAttrs isSelectedRuntimeNode (nebulaRuntimePlan.nodes or { });
    overlays =
      lib.filterAttrs
        (_overlayId: overlay: builtins.elem "${overlay.enterpriseName or ""}::${overlay.siteName or ""}" selectedSiteKeys)
        (nebulaRuntimePlan.overlays or { });
  };
  siteCDmzLighthouseEndpoint4 = "10.90.10.100";
  applyHetznerLighthouseEndpoint = value:
    if builtins.isAttrs value && builtins.hasAttr "lighthouse" value && builtins.isAttrs value.lighthouse then
      lib.recursiveUpdate value {
        lighthouse.endpoint = siteCDmzLighthouseEndpoint4;
        lighthouse.endpoint6 = "";
      }
    else
      value;
  selectedNebulaRuntimePlanForHetzner = selectedNebulaRuntimePlan // {
    nodes = lib.mapAttrs (_: applyHetznerLighthouseEndpoint) (selectedNebulaRuntimePlan.nodes or { });
    overlays = lib.mapAttrs (_: applyHetznerLighthouseEndpoint) (selectedNebulaRuntimePlan.overlays or { });
  };
  builders = import ../../../nixos-shell-vm/s-router-test/modules/container-builders.nix {
    inherit lib;
    pkgs = pkgsForRenderer;
    mkNebulaRuntimeService = nodeName:
      nebulaRenderer.buildNebulaRuntimeNixosModule {
        pkgs = pkgsForRenderer;
        inherit nodeName;
      };
  };
  overlayContainers = import ../../../nixos-shell-vm/s-router-test/modules/overlay-containers.nix {
    inherit lib renderedContainers;
    nebulaRuntimePlan = selectedNebulaRuntimePlanForHetzner;
    inherit (builders) mkNebulaNode mkNebulaProfileMount mkNebulaRuntimeAddon;
  };
  nebulaBootstrapModule = nebulaRenderer.buildNebulaBootstrapNixosModule {
    pkgs = pkgsForRenderer;
    nebulaRuntimePlan = selectedNebulaRuntimePlanForHetzner;
    externalLighthousePublicIpv4SecretPath = "/run/secrets/hetzner-lighthouse-public-ipv4";
    externalLighthousePublicIpv6SecretPath = "/run/secrets/hetzner-public-ipv6";
    externalPortForwardPublicIpv4SecretPath = "/run/secrets/hetzner-public-ipv4";
    externalPortForwardPublicIpv6SecretPath = "/run/secrets/hetzner-public-ipv6";
    externalPortForwardNodeNames = [ "c-router-nebula-core" ];
    externalRuntimeNodeNames = [ "c-router-nebula-core" ];
    runtimeListenHosts = {
      c-router-nebula-core = internalWanForwardTarget;
    };
    externalRemoteLighthouseEndpoint4 = siteCDmzLighthouseEndpoint4;
    externalRemoteLighthouseEndpoint6 = "";
  };
  externalLighthouseModule = nebulaRenderer.buildExternalLighthouseNixosModule {
    pkgs = pkgsForRenderer;
    nebulaRuntimePlan = selectedNebulaRuntimePlanForHetzner;
  };
  require = name: value:
    if value == null || value == "" || value == [ ] then
      throw "s-router-hetzner-anywhere: runtime.nix must set ${name} before deployment"
    else
      value;
  publicIPv4Gateway = require "publicIPv4Gateway" (runtime.publicIPv4Gateway or null);
  runtimeSecretsDir = "/persist/s-router-test-runtime";
  publicIPv4SecretPath = "${runtimeSecretsDir}/hetzner-public-ipv4";
  lighthousePublicIPv4SecretPath = "${runtimeSecretsDir}/hetzner-lighthouse-public-ipv4";
  publicIPv6SecretPath = "${runtimeSecretsDir}/hetzner-public-ipv6";
  publicIPv6AddressSecretPath = "${runtimeSecretsDir}/hetzner-public-ipv6-address";
  routedIPv6PrefixesSecretPath = "${runtimeSecretsDir}/hetzner-routed-ipv6-prefixes";
  primaryInterfaceMac = require "primaryInterfaceMac" (runtime.primaryInterfaceMac or null);
  primaryInterfaceFallback = require "primaryInterface" (runtime.primaryInterface or null);
  primaryInterfaceMatchConfig = {
    MACAddress = primaryInterfaceMac;
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
  internalWanForwardTarget = "${internalWanPrefix}.4";
  renderedAndOverlayContainers = lib.recursiveUpdate renderedContainers overlayContainers;
  accessPrefixRuntimeSecrets = import ./access-prefix-runtime-secrets.nix {
    inherit lib runtimeSecretsDir;
    controlPlanes = [
      (builtHost.controlPlaneOut or { })
      (localRouterHost.controlPlaneOut or { })
    ];
    containers = renderedAndOverlayContainers;
  };
  publicIngressModule =
    import "${inputs.network-renderer-nixos}/s88/ControlModule/module/public-ingress.nix" {
      inherit lib;
      pkgs = pkgsForRenderer;
      controlPlane = builtHost.controlPlaneOut or { };
      inventory = builtHost.globalInventory or { };
      hostName = "s-router-hetzner-anywhere";
      runtimeFacts.publicIngress = {
        snatSourceCidr4 = "${internalWanPrefix}.0/24";
        services.esp0xdeadbeef.site-c.dmz-nebula = {
          publicIPv4SecretPath = "/run/secrets/hetzner-lighthouse-public-ipv4";
          gateway4 = "${internalWanPrefix}.3";
        };
        runtimeForwards = [
          {
            publicIPv4SecretPath = "/run/secrets/hetzner-public-ipv4";
            targetIPv4 = internalWanForwardTarget;
            protocols = [
              "tcp"
              "udp"
            ];
            protectServiceDports = false;
            exceptTcpDports = [ 22 ];
            inputDports = [ 4242 ];
            containerInterface = {
              container = "c-router-nebula-core";
              name = "portforward";
              hostBridge = "br-wan";
              localAddress = "${internalWanForwardTarget}/24";
              gateway4 = "${internalWanPrefix}.1";
              routeMetric = 5000;
            };
          }
        ];
      };
    };
  hetznerContainerOverrides = {
    c-router-core = let
      baseContainer = renderedAndOverlayContainers.c-router-core or { };
      baseConfig = baseContainer.config or { };
    in {
      config = { pkgs, ... }: {
        imports = [ baseConfig ];
        systemd.network.networks."10-eth0" = lib.mkForce {
          matchConfig.Name = "eth0";
          networkConfig = {
            DHCP = "no";
            IPv6AcceptRA = false;
          };
          address = [ "${internalWanPrefix}.3/24" ];
          routes = [ { Gateway = "${internalWanPrefix}.1"; } ];
        };
      };
    };
  };
in
{
  imports = [
    inputs.disko.nixosModules.disko
    (builtHost.artifactModule or { })
    ../disko.nix
    ../hardware.nix
  ];

  config = lib.mkMerge [
	    externalLighthouseModule
	    nebulaBootstrapModule
      publicIngressModule
	    {

      assertions = [
        {
          assertion = runtime.publicIPv4Gateway != null && runtime.primaryInterfaceMac != null && runtime.primaryInterface != null;
          message = "runtime.nix must be generated from the Hetzner spawn output without public address literals";
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
            matchConfig.Name = "br-wan";
            linkConfig = {
              ActivationPolicy = "always-up";
              RequiredForOnline = "no";
            };
            networkConfig = {
              DHCP = "no";
              DHCPServer = true;
              ConfigureWithoutCarrier = true;
              IPv4Forwarding = true;
              IPv6AcceptRA = false;
            };
            address = [ internalWanAddress ];
            dhcpServerConfig = {
              PoolOffset = 10;
              PoolSize = 32;
              EmitDNS = false;
            };
          };
        };
      systemd.tmpfiles.rules = [
        "d ${runtimeSecretsDir} 0700 root root -"
        "d /run/secrets 0700 root root -"
        "L+ /run/secrets/hetzner-lighthouse-public-ipv4 - - - - ${lighthousePublicIPv4SecretPath}"
        "L+ /run/secrets/hetzner-public-ipv4 - - - - ${publicIPv4SecretPath}"
        "L+ /run/secrets/hetzner-public-ipv6 - - - - ${publicIPv6SecretPath}"
      ] ++ accessPrefixRuntimeSecrets.tmpfilesRules;
      systemd.services.hetzner-runtime-addresses = {
        description = "Apply Hetzner runtime public addresses from root-only runtime files";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-networkd.service" ];
        wants = [ "systemd-networkd.service" ];
        path = with pkgsForRenderer; [
          coreutils
          gnugrep
          iproute2
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -euo pipefail

          primary_if=""
          for candidate in /sys/class/net/*; do
            [ -e "$candidate/address" ] || continue
            if [ "$(tr '[:upper:]' '[:lower:]' < "$candidate/address")" = "${lib.toLower primaryInterfaceMac}" ]; then
              primary_if="''${candidate##*/}"
              break
            fi
          done
          if [ -z "$primary_if" ] && [ -e "/sys/class/net/${primaryInterfaceFallback}" ]; then
            primary_if="${primaryInterfaceFallback}"
          fi
          if [ -z "$primary_if" ]; then
            echo "could not find Hetzner primary interface with MAC ${primaryInterfaceMac}" >&2
            exit 1
          fi

          public4="$(tr -d '\n' < ${publicIPv4SecretPath})"
          public6_addr="$(tr -d '\n' < ${publicIPv6AddressSecretPath})"

          ip address replace "$public4/32" dev "$primary_if"
          ip address replace "$public6_addr" dev "$primary_if"

          if [ -s ${lighthousePublicIPv4SecretPath} ]; then
            lighthouse4="$(tr -d '\n' < ${lighthousePublicIPv4SecretPath})"
            ip address replace "$lighthouse4/32" dev "$primary_if"
          fi

          if [ -s ${routedIPv6PrefixesSecretPath} ]; then
            while IFS= read -r prefix; do
              [ -n "$prefix" ] || continue
              case "$prefix" in
                *::/64)
                  ip address replace "''${prefix%::/64}::1/128" dev "$primary_if"
                  ;;
              esac
            done < ${routedIPv6PrefixesSecretPath}
          fi

          ip route replace ${publicIPv4Gateway}/32 dev "$primary_if" scope link
          ip route replace default via ${publicIPv4Gateway} dev "$primary_if"
          ip -6 route replace default via fe80::1 dev "$primary_if"
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

      environment.systemPackages = with pkgsForRenderer; [
        bind
        conntrack-tools
        curl
        ethtool
        gron
        iproute2
        iptables
        iputils
        jq
        lsof
        mtr
        netcat-openbsd
        nftables
        procps
        ripgrep
        socat
        strace
        tcpdump
        traceroute
      ];

      environment.etc."s-router-test/hetzner-runtime.json".text = builtins.toJSON (
        runtime
        // {
          publicIPv4SecretPath = publicIPv4SecretPath;
          publicIPv6SecretPath = publicIPv6SecretPath;
          publicIPv6AddressSecretPath = publicIPv6AddressSecretPath;
          routedIPv6PrefixesSecretPath = routedIPv6PrefixesSecretPath;
        }
      );
	      environment.etc."network-renderer/network-renderer-nebula.json".text = builtins.toJSON {
	        overlays = builtins.attrNames (selectedNebulaRuntimePlanForHetzner.overlays or { });
	        nodes = builtins.attrNames (selectedNebulaRuntimePlanForHetzner.nodes or { });
	      };

	      containers = lib.recursiveUpdate
	        accessPrefixRuntimeSecrets.containers
	        hetznerContainerOverrides;

	      system.stateVersion = "25.11";
	    }
  ];
}
