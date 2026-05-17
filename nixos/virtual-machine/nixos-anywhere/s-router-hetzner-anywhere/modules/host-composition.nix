{ inputs
, lib
, outPath
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
  selectedNebulaRuntimePlanForHetzner = selectedNebulaRuntimePlan;
  builders = import ../../../nixos-shell-vm/s-router-test/modules/container-builders.nix {
    inherit lib;
    pkgs = pkgsForRenderer;
    mkNebulaRuntimeService = nodeName:
      nebulaRenderer.buildNebulaRuntimeNixosModule {
        pkgs = pkgsForRenderer;
        inherit nodeName;
        runtimeNode = selectedNebulaRuntimePlanForHetzner.nodes.${nodeName};
      };
  };
  overlayContainers = import ../../../nixos-shell-vm/s-router-test/modules/overlay-containers.nix {
    inherit lib renderedContainers;
    nebulaRuntimePlan = selectedNebulaRuntimePlanForHetzner;
    inherit (builders) mkNebulaNode mkNebulaProfileMount mkNebulaRuntimeAddon;
  };
  realizationNodes = (((builtHost.globalInventory or { }).realization or { }).nodes or { });
  hetznerRealizationNodeFor = logicalName:
    let
      matches =
        lib.filterAttrs
          (
            _nodeName: node:
            (node.host or null) == "s-router-hetzner-anywhere"
            && ((node.logicalNode or { }).name or null) == logicalName
          )
          realizationNodes;
    in
      if matches == { } then
        throw "missing ${logicalName} realization node on s-router-hetzner-anywhere"
      else
        builtins.head (builtins.attrValues matches);
  runtimeContainerNameFor = logicalName:
    let
      node = hetznerRealizationNodeFor logicalName;
    in
      node.targetContainer or (node.runtimeName or logicalName);
  hetzCoreContainerName = runtimeContainerNameFor "hetz-router-core";
  hetzNebulaCoreContainerName = runtimeContainerNameFor "hetz-router-nebula-core";
  nebulaBootstrapModule = nebulaRenderer.buildNebulaBootstrapNixosModule {
    pkgs = pkgsForRenderer;
    nebulaRuntimePlan = selectedNebulaRuntimePlanForHetzner;
    externalLighthousePublicIpv4SecretPath = "/run/secrets/hetzner-lighthouse-public-ipv4";
    externalLighthousePublicIpv6SecretPath = "/run/secrets/hetzner-public-ipv6";
    externalPortForwardPublicIpv4SecretPath = "/run/secrets/hetzner-public-ipv4";
    externalPortForwardPublicIpv6SecretPath = "/run/secrets/hetzner-public-ipv6";
    externalPortForwardNodeNames = [ ];
    externalRuntimeNodeNames = [ hetzNebulaCoreContainerName ];
    externalRemoteLighthouseEndpoint4SecretPath = "/run/secrets/hetzner-lighthouse-public-ipv4";
    externalRemoteLighthouseEndpoint6SecretPath = "/run/secrets/hetzner-public-ipv6";
    externalSuppressPublicLighthouseStaticMap = true;
    sopsProfileSecretPrefix = "nebula-profile";
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
  operatorAuthorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA1Rmk/3OrwWB5qvWrltIDGgK2vxQIXfRtPkAg56gHB1 deadbeef@l-x13s"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMgBgeVe/DSMZQAY8iS1D5Db3IbyteDSW+l79ZFD8Rmg deadbeef@l-esp"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJwxQYzAV73hk/YIet+5EfgS6RdbkA0wyL5J8G8SjAY0 root@s-router-test"
  ];
  publicIPv4SecretPath = "${runtimeSecretsDir}/hetzner-public-ipv4";
  lighthousePublicIPv4SecretPath = "${runtimeSecretsDir}/hetzner-lighthouse-public-ipv4";
  publicIPv6SecretPath = "${runtimeSecretsDir}/hetzner-public-ipv6";
  publicIPv6AddressSecretPath = "${runtimeSecretsDir}/hetzner-public-ipv6-address";
  routedIPv6PrefixesSecretPath = "${runtimeSecretsDir}/hetzner-routed-ipv6-prefixes";
  rootPasswordHashPath = "${runtimeSecretsDir}/hetzner-root-password-hash";
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
  internalWan = import ./hetzner-internal-wan.nix {
    inherit lib;
    inventory = builtHost.globalInventory or { };
    hostName = "s-router-hetzner-anywhere";
    coreNodeName = "hetz-router-core";
  };
  hetzForwardingSite =
    (((builtHost.forwardingOut or { }).enterprise or { }).esp or { }).site.hetz or { };
  hostNatIngress =
    if builtins.isAttrs (hetzForwardingSite.hostNatIngress or null) && hetzForwardingSite.hostNatIngress != { } then
      hetzForwardingSite.hostNatIngress
    else
      throw "s-router-hetzner-anywhere: forwarding output must provide esp.hetz.hostNatIngress";
  hostNatIngressEnabled = hostNatIngress.enabled or false;
  hostNatIngressTargetNode =
    if hostNatIngressEnabled then
      hostNatIngress.targetNode or (throw "s-router-hetzner-anywhere: hostNatIngress.targetNode is required")
    else
      "hetz-router-core";
  hostNatIngressUplink =
    if hostNatIngressEnabled then
      hostNatIngress.uplink or (throw "s-router-hetzner-anywhere: hostNatIngress.uplink is required")
    else
      "wan";
  hostNatIngressTargetWan = import ./hetzner-internal-wan.nix {
    inherit lib;
    inventory = builtHost.globalInventory or { };
    hostName = "s-router-hetzner-anywhere";
    coreNodeName = hostNatIngressTargetNode;
    uplinkName = hostNatIngressUplink;
  };
  hostNatIngressReservedTcpDports =
    lib.sort (a: b: a < b) (
      lib.unique (
        lib.concatMap
          (port:
            if (port.proto or null) == "tcp" then
              port.dports or [ ]
            else
              [ ])
          (hostNatIngress.hostReservedPorts or [ ])
      )
    );
  internalWanCidr4 = hostNatIngressTargetWan.hostAddress4;
  internalWanForwardTarget = hostNatIngressTargetWan.coreAddress4Bare;
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
        snatSourceCidr4 = internalWanCidr4;
        services.esp0xdeadbeef.hetz.dmz-nebula = {
          publicIPv4SecretPath = "/run/secrets/hetzner-lighthouse-public-ipv4";
          gateway4 = internalWanForwardTarget;
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
            exceptTcpDports = hostNatIngressReservedTcpDports;
          }
        ];
      };
    };
  hetznerContainerOverrides = {
    ${hetzCoreContainerName} = let
      baseContainer = renderedAndOverlayContainers.${hetzCoreContainerName} or { };
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
          address = [
            internalWan.coreAddress4
            internalWan.coreAddress6
          ];
          routes = [
            { Gateway = internalWan.coreGateway4; }
            { Gateway = internalWan.coreGateway6; }
          ];
        };
      };
    };
  };
in
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.impermanence.nixosModules.impermanence
    inputs.sops-nix.nixosModules.sops
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
      sops.defaultSopsFile = "${outPath}/secrets/s-router-test.yaml";
      sops.age.sshKeyPaths = [ "/persist/root/.ssh/id_ed25519" ];
      sops.age.keyFile = "/persist/root/.config/sops/age/keys.txt";
      fileSystems."/boot".neededForBoot = true;
      fileSystems."/nix".neededForBoot = true;
      fileSystems."/persist".neededForBoot = true;
      environment.persistence."/persist" = {
        hideMounts = true;
        directories = [
          "/root/.ssh"
          "/var/lib/nixos"
          "/var/lib/systemd"
        ];
        files = [
          "/etc/machine-id"
        ];
      };
      system.activationScripts.prepareHetznerImpermanenceMachineId = {
        deps = [ "createPersistentStorageDirs" ];
        text = ''
          install -d -m 0755 /persist/etc
          if [ -e /etc/machine-id ] && [ ! -s /persist/etc/machine-id ]; then
            install -D -m 0444 /etc/machine-id /persist/etc/machine-id
          fi
          if [ ! -s /persist/etc/machine-id ]; then
            ${pkgsForRenderer.systemd}/bin/systemd-id128 new > /persist/etc/machine-id
            chmod 0444 /persist/etc/machine-id
          fi
          rm -f /etc/machine-id
        '';
      };
      system.activationScripts.persist-files.deps = [
        "prepareHetznerImpermanenceMachineId"
      ];
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
              IPv6Forwarding = true;
              IPv6AcceptRA = false;
            };
            address = [
              internalWan.hostAddress4
              internalWan.hostAddress6
            ];
            dhcpServerConfig = {
              PoolOffset = 10;
              PoolSize = 32;
              EmitDNS = false;
            };
          };
        };
      systemd.tmpfiles.rules = [
        "d /persist/etc 0755 root root -"
        "d /persist/etc/ssh 0755 root root -"
        "d /persist/root 0700 root root -"
        "d /persist/root/.ssh 0700 root root -"
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
          ip link set dev "$primary_if" up
          ip link set dev br-wan up

          public4="$(tr -d '\n' < ${publicIPv4SecretPath})"
          public6_prefix="$(tr -d '\n' < ${publicIPv6SecretPath})"
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
              if [ "$prefix" = "$public6_prefix" ]; then
                continue
              fi
              case "$prefix" in
                *::/64)
                  ip address replace "''${prefix%::/64}::1/128" dev "$primary_if"
                  ip -6 route replace "$prefix" via ${internalWan.coreAddress6Bare} dev br-wan onlink
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

      users.users.root = {
        hashedPasswordFile = rootPasswordHashPath;
        openssh.authorizedKeys.keys =
          lib.unique (operatorAuthorizedKeys ++ require "authorizedKeys" runtime.authorizedKeys);
      };

      services.openssh = {
        enable = true;
        hostKeys = [
          {
            type = "ed25519";
            path = "/persist/etc/ssh/ssh_host_ed25519_key";
          }
          {
            type = "rsa";
            bits = 4096;
            path = "/persist/etc/ssh/ssh_host_rsa_key";
          }
        ];
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
        dig
        ethtool
        gron
        iproute2
        iptables
        iputils
        jq
        lsof
        mtr
        netcat-openbsd
        neovim
        nftables
        procps
        ripgrep
        socat
        strace
        tcpdump
        traceroute
        vim
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
