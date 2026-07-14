{
  description = "esp0xdeadbeef nix config";

  inputs = {
    nixpkgs-stable = {
      url = "github:nixos/nixpkgs/nixos-26.05";
    };

    nixpkgs-unstable = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };

    nixpkgs = {
      # url = "github:nixos/nixpkgs/nixos-24.11";
      url = "github:nixos/nixpkgs/nixos-26.05";
      #url = "github:nixos/nixpkgs/nixos-unstable";
    };

    nixos-router-vpn-gateway = {
      url = "github:esp0xdeadbeef/nixos-router-vpn-gateway";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    nixos-mailserver = {
      url = "gitlab:simple-nixos-mailserver/nixos-mailserver/nixos-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    network-renderer-nebula = {
      url = "github:esp0xdeadbeef/network-renderer-nebula";
    };

    network-renderer-wireguard = {
      url = "github:esp0xdeadbeef/network-renderer-wireguard";
    };

    network-renderer-access-endpoint-nixos = {
      url = "github:esp0xdeadbeef/network-renderer-access-endpoint-nixos";
    };

    network-control-plane-model = {
      url = "github:esp0xdeadbeef/network-control-plane-model";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    network-renderer-nixos = {
      url = "github:esp0xdeadbeef/network-renderer-nixos";
    };

    network-compiler-prod = {
      url = "github:esp0xdeadbeef/network-compiler/0745f6ebc3e86c0970f74bd52fb209d9fdd8e27d";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    network-forwarding-model-prod = {
      url = "github:esp0xdeadbeef/network-forwarding-model/2f92f74bec0e8e9a03f840dc73a304b963894638";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-compiler.follows = "network-compiler-prod";
    };

    network-control-plane-model-prod = {
      url = "github:esp0xdeadbeef/network-control-plane-model/bf126c4aac782843a21be28a2d9b82384d15e6be";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-forwarding-model.follows = "network-forwarding-model-prod";
    };

    nixos-network-compiler-prod = {
      url = "github:esp0xdeadbeef/nixos-network-compiler/0745f6ebc3e86c0970f74bd52fb209d9fdd8e27d";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    network-renderer-nixos-prod = {
      url = "github:esp0xdeadbeef/network-renderer-nixos/38ae8e6c68041a76d95e4bbc93c921377afb1837";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.network-control-plane-model.follows = "network-control-plane-model-prod";
      inputs.network-forwarding-model.follows = "network-forwarding-model-prod";
      inputs.nixos-network-compiler.follows = "nixos-network-compiler-prod";
    };

    network-renderer-containerlab-linux-backend = {
      url = "github:esp0xdeadbeef/network-renderer-containerlab-linux-backend";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
    };

    cheat-sheets = {
      url = "github:esp0xdeadbeef/cheat.sheets";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    network-labs = {
      url = "github:esp0xdeadbeef/network-labs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home manager
    #home-manager = {
    #  url = "github:nix-community/home-manager";
    #  inputs.nixpkgs.follows = "nixpkgs";
    #};

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # sops:
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # hardware:
    hardware = {
      url = "github:nixos/nixos-hardware";
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware = {
      url = "github:nixos/nixos-hardware";
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware-x13s = {
      url = "github:NixOS/nixos-hardware";
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence = {
      url = "github:nix-community/impermanence";
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # To get spotify / widevine working on a x13s laptop:
    nixos-aarch64-widevine = {
      url = "github:epetousis/nixos-aarch64-widevine";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    # integrated:
    # nix run github:Mic92/nixos-shell -- --flake .#vm
    nixos-shell = {
      url = "github:Mic92/nixos-shell";
    };
  };

  outputs =
    { self
    , nixpkgs
    , home-manager
    , ...
    }@inputs:
    let
      lib = nixpkgs.lib;
      inherit (self) outputs;

      systems = [
        "aarch64-linux"
        "i686-linux"
        "x86_64-linux"
        "aarch64-darwin"
      ];

      forAllSystems = lib.genAttrs systems;

      root = self.outPath;

      repoLib = import ./library/imports.nix { inherit lib; };

      profiles = import ./profiles;

      sRouterVlan2RuntimeHosts = [
        "s-router-clab"
        "s-router-nixos"
        "s-router-test-clients"
      ];

      # Host architecture overrides.
      #
      # Most hosts are x86_64. The ThinkPad X13s is Qualcomm ARM64, so evaluating
      # it as x86_64-linux is wrong.
      hostSystems = {
        l-portal = "aarch64-linux";
      };

      hostSystemFor = name: hostSystems.${name} or "x86_64-linux";

      # ------------------------------------------------------------
      # STRUCTURAL HOST ROOTS (semantic, stable)
      # ------------------------------------------------------------
      hostRoots = [
        "nixos/laptop"
        "nixos/server"
        "nixos/virtual-machine/nixos-shell-vm"
        "nixos/virtual-machine/dedicated-vm"
        "nixos/virtual-machine/nixos-anywhere"
      ];

      # List direct subdirectories
      listDirs =
        path:
        let
          abs = "${root}/${path}";
        in
        if builtins.pathExists abs then
          lib.filterAttrs (_: v: v == "directory") (builtins.readDir abs)
        else
          { };

      # Discover all hosts automatically
      hosts = lib.foldl'
        (
          acc: base: acc // lib.mapAttrs (name: _: "${base}/${name}") (listDirs base)
        )
        { }
        hostRoots;

      allHostAbs = lib.mapAttrsToList (_: v: "${root}/${v}") hosts;

      # ------------------------------------------------------------
      # MINIMAL SOURCE PER HOST
      # ------------------------------------------------------------
      vmSourceForHost =
        name:
        let
          mine = "${root}/${hosts.${name}}";
          others = lib.filter (p: p != mine) allHostAbs;
        in
        builtins.path {
          name = "esp0xdeadbeef-vm-src-${name}";
          path = root;
          filter =
            p: _:
            let
              inOther = lib.any (o: lib.hasPrefix o p) others;
              inGit = lib.hasPrefix "${root}/.git" p;
            in
            # include everything EXCEPT other hosts and .git
              !(inOther || inGit);
        };

      sRouterVlan2RuntimeValidation =
        hostName: config:
        let
          network = config.systemd.network;
          netdevs = builtins.attrValues (network.netdevs or { });
          networks = builtins.attrValues (network.networks or { });
          networkEntries =
            map
              (name: {
                inherit name;
                value = network.networks.${name};
              })
              (builtins.attrNames (network.networks or { }));

          count = pred: values: lib.length (lib.filter pred values);
          has = value: values: builtins.elem value values;
          atLeastOne = pred: values: count pred values > 0;
          firstNetwork = pred: entries: lib.findFirst (entry: pred entry.value) null entries;

          isDisabled = value: value == false || value == "no" || value == "false";
          isIpv4Dhcp = value: value == true || value == "yes" || value == "ipv4";

          vlanIf = "eth0.2";
          vlanId = 2;
          bridge = "vlan2";

          vlanNetdev = dev:
            (dev.netdevConfig.Kind or null) == "vlan"
            && (dev.netdevConfig.Name or null) == vlanIf
            && (dev.vlanConfig.Id or null) == vlanId;

          bridgeNetdev = dev:
            (dev.netdevConfig.Kind or null) == "bridge"
            && (dev.netdevConfig.Name or null) == bridge;

          parentNetwork = net:
            (net.matchConfig.Name or null) == "eth0"
            && has vlanIf (net.networkConfig.VLAN or [ ])
            && isDisabled (net.networkConfig.DHCP or "no");

          vlanNetwork = net:
            (net.matchConfig.Name or null) == vlanIf
            && (net.networkConfig.Bridge or null) == bridge
            && isDisabled (net.networkConfig.DHCP or "no");

          effectiveBridgeNetwork = firstNetwork (net: (net.matchConfig.Name or null) == bridge) networkEntries;
          effectiveBridgeNetworkHasIpv4Dhcp =
            effectiveBridgeNetwork != null && isIpv4Dhcp (effectiveBridgeNetwork.value.networkConfig.DHCP or null);
        in
        {
          errors =
            lib.optionals (!atLeastOne vlanNetdev netdevs) [
              "${hostName}: runtime must define at least one VLAN netdev eth0.2 with vlanConfig.Id = 2"
            ]
            ++ lib.optionals (!atLeastOne bridgeNetdev netdevs) [
              "${hostName}: runtime must define at least one bridge netdev vlan2"
            ]
            ++ lib.optionals (!atLeastOne parentNetwork networks) [
              "${hostName}: runtime must define at least one eth0 network that attaches eth0.2 and disables DHCP"
            ]
            ++ lib.optionals (!atLeastOne vlanNetwork networks) [
              "${hostName}: runtime must define at least one eth0.2 network enslaved into vlan2 with DHCP disabled"
            ]
            ++ lib.optionals (!effectiveBridgeNetworkHasIpv4Dhcp) [
              "${hostName}: runtime first matching vlan2 network must use IPv4 DHCP with optional IPv6 SLAAC/RA client"
            ];
        };

      sRouterVlan2RuntimeGate =
        hostName:
        { config, ... }:
        let
          validation = sRouterVlan2RuntimeValidation hostName config;
        in
        {
          assertions = [
            {
              assertion = validation.errors == [ ];
              message = builtins.concatStringsSep "; " validation.errors;
            }
          ];
        };

    in
    {
      lib = repoLib // {
        inherit vmSourceForHost hosts;
      };

      checks.x86_64-linux =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;

          mkSRouterVlan2OutputCheck =
            hostName:
            let
              require = cond: message: if cond then true else throw message;
              validation = sRouterVlan2RuntimeValidation hostName self.nixosConfigurations.${hostName}.config;

              validated =
                require
                  (validation.errors == [ ])
                  (builtins.concatStringsSep "; " validation.errors);
            in
            pkgs.runCommand (if validated then "${hostName}-vlan2-output-check" else "unreachable") { } ''
              printf '%s\n' '${hostName}: VLAN2 output check passed' > "$out"
            '';
        in
        lib.listToAttrs (map
          (hostName: {
            name = "${hostName}-vlan2-output";
            value = mkSRouterVlan2OutputCheck hostName;
          })
          sRouterVlan2RuntimeHosts);

      packages =
        if builtins.pathExists ./pkgs then
          forAllSystems
            (
              system:
              let
                pkgs = import nixpkgs {
                  inherit system;
                  config = {
                    allowUnfree = true;
                    android_sdk.accept_license = true;
                  };
                };
              in
              import ./pkgs {
                inherit pkgs system;
                inherit (pkgs) lib;
              }
            )
        else
          { };

      formatter = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.writeShellApplication {
          name = "fmt-nix-only";
          runtimeInputs = [ pkgs.nixpkgs-fmt ];
          text = ''
            if [ "$#" -eq 0 ]; then
              exec nixpkgs-fmt .
            fi

            nix_files=()
            for path in "$@"; do
              case "$path" in
                *.nix) nix_files+=("$path") ;;
              esac
            done

            if [ "''${#nix_files[@]}" -eq 0 ]; then
              echo "No .nix files supplied; skipping formatter." >&2
              exit 0
            fi

            exec nixpkgs-fmt "''${nix_files[@]}"
          '';
        }
      );

      overlays =
        if builtins.pathExists ./overlays then
          import ./overlays
            {
              inherit inputs;
              outPath = root;
            }
        else
          { };

      nixosModules = if builtins.pathExists ./modules/nixos then import ./modules/nixos else { };
      homeManagerModules =
        if builtins.pathExists ./modules/home-manager then
          import ./modules/home-manager { outPath = root; }
        else
          { };

      inherit profiles;

      # ------------------------------------------------------------
      # GENERATED NIXOS CONFIGURATIONS
      # ------------------------------------------------------------
      nixosConfigurations = lib.mapAttrs
        (
          name: path:
            nixpkgs.lib.nixosSystem {
              system = hostSystemFor name;

              specialArgs = {
                inherit
                  inputs
                  outputs
                  profiles
                  self
                  name
                  ;
                outPath = self.outPath;
              };

              modules = [
                outputs.nixosModules.pythonPycachePrefix
                (./. + "/${path}")
              ]
              ++ lib.optionals (builtins.elem name sRouterVlan2RuntimeHosts) [
                (sRouterVlan2RuntimeGate name)
              ];
            }
        )
        hosts;
    };
}
