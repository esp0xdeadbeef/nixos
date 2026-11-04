{ inputs
, lib
, config
, pkgs
, relativeRepo
, profiles
, ...
}:
let
  system = "x86_64-linux";
  labSource = "active-lab";
  hostName = "s-router-test-clients";
  vmNics = [
    {
      nicId = "nic0";
      bridge = "vmbr4";
    }
    {
      nicId = "nic1";
      bridge = "vmbr4";
    }
    {
      nicId = "nic2";
      bridge = "vmbr4";
    }
    {
      nicId = "nic3";
      bridge = "vmbr4";
    }
    {
      nicId = "nic4";
      bridge = "vmbr4";
    }
    {
      nicId = "nic5";
      bridge = "vmbr4";
    }
  ];
  labPath = "${inputs.network-labs}/${labSource}";
  intentPath = "${labPath}/intent-${hostName}.nix";
  inventoryPath = "${labPath}/inventory-${hostName}.nix";
  clientsPath = "${labPath}/clients-${hostName}.nix";

  cpmLib = inputs.network-control-plane-model.libBySystem.${system};
  cpmBuilt = cpmLib.compileAndBuildFromPaths {
    inputPath = intentPath;
    inherit inventoryPath;
  };

  controlPlaneArtifact =
    let
      artifactDigest = builtins.hashString "sha256" (builtins.toJSON cpmBuilt);
    in
    {
      kind = "network-control-plane-artifact";
      artifactIdentity = artifactDigest;
      inherit artifactDigest;
      control_plane_model = cpmBuilt;
      authorityConflicts = [ ];
      provenance = {
        producer = "nixos/${hostName}";
        source = "network-control-plane-model";
      };
    };

  canonicalBundle = inputs.network-realization-model.lib.realize {
    input = controlPlaneArtifact;
    requestScope = {
      kind = "complete-artifact";
      identity = hostName;
    };
    rootLockIdentity = builtins.hashString "sha256" (builtins.readFile ../../../../flake.lock);
    producerRevision =
      inputs.network-realization-model.rev
        or inputs.network-realization-model.dirtyRev
        or "uncommitted";
  };

  producer = import (relativeRepo.module "library/10-vms/nixos-shell-vm/renderer-pipeline-producer.nix") {
    inherit lib;
  };

  platformBinding = producer.vmNicsPlatformBinding {
    inherit hostName vmNics;
    bundle = canonicalBundle;
    target = "access-endpoint-nixos";
  };
in
{
  imports = [
    (relativeRepo.module "library/10-vms/nixos-shell-vm/host-config-routers-without-network")
    profiles.nixos.network.router-vlan2-runtime-contract

    (inputs.network-renderer-nixos.libBySystem.${system}.renderer.canonical.hostModule {
      inherit hostName;
      bundle = canonicalBundle;
    })

    (inputs.network-renderer-access-endpoint-nixos.libBySystem.${system}.renderer.canonical.hostModule {
      inherit hostName labSource platformBinding;

      bundle = canonicalBundle;
      inventory = inventoryPath;
      clients = clientsPath;
      sops = "${labPath}/sops-routing-${hostName}.nix";

    })
  ];

  # Dedicated test fixture: request a real DHCP lease from the access-local
  # Kea server and put the client on the same access segment as the lab
  # clients. This belongs on s-router-test-clients, not on the router host.
  options.sRouterTestClientsDhcpClient.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Run the lab DHCP test client on the access-local bridge";
  };

  config = lib.mkIf config.sRouterTestClientsDhcpClient.enable {
    # Second fixture on the *recursive* lane. The renderer-emitted
    # `recursive-dns-nixos-client` cannot be extended from the host (FS-983
    # keeps its container definition renderer-owned), so this container is
    # host-declared and asserts the modelled `recursive-client` contract from
    # the only side the host is allowed to own: its own test container.
    containers.dhcp-recursive-test = {
      autoStart = true;
      privateNetwork = true;
      hostBridge = "dns545nr";
      config = {
        system.stateVersion = "26.05";
        networking.useHostResolvConf = false;
        services.resolved.enable = true;
        systemd.network.enable = true;
        systemd.network.networks."10-eth0" = {
          matchConfig.Name = "eth0";
          networkConfig.DHCP = "ipv4";
          dhcpV4Config.UseDNS = false;
        };
        systemd.services.recursive-lane-assert = {
          description = "Assert the recursive-client lane lease and web egress";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          wants = [ "network.target" ];
          path = with pkgs; [
            bash
            coreutils
            curl
            gawk
            iproute2
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            set -u

            gw=""
            i=0
            while [ "$i" -lt 60 ]; do
              gw=$(ip -4 route show default | awk '/^default/ { print $3; exit }')
              [ -n "$gw" ] && break
              i=$((i + 1))
              sleep 1
            done
            if [ -z "$gw" ]; then
              echo "ASSERT FAIL: recursive lane got no DHCP gateway" >&2
              exit 1
            fi
            echo "recursive lease gateway: $gw"

            i=0
            while [ "$i" -lt 30 ]; do
              if curl -m 8 -sS -o /dev/null http://1.1.1.1 2>/dev/null; then
                echo "ASSERT OK: recursive-client web egress works"
                exit 0
              fi
              i=$((i + 1))
              sleep 2
            done
            echo "ASSERT FAIL: recursive-client web egress blocked" >&2
            exit 1
          '';
        };
      };
    };

    containers.dhcp-test = {
      autoStart = true;
      privateNetwork = true;
      hostBridge = "dns545nl";
      config = {
        system.stateVersion = "26.05";
        networking.useHostResolvConf = false;
        services.resolved.enable = true;
        systemd.network.enable = true;
        systemd.network.networks."10-eth0" = {
          matchConfig.Name = "eth0";
          networkConfig.DHCP = "ipv4";
          dhcpV4Config.UseDNS = false;
        };

        # Prove the modelled service, not just the lease.
        #
        # `local-client` is allowed DNS to the access-local resolver (FS-540
        # relation `local-client-to-access`, dports 53) and nothing else: the
        # access-local input policy is `drop` with only DHCP + DNS permitted,
        # so ICMP is blocked BY DESIGN. Asserting the allowed path (TCP/53 to
        # the DHCP-supplied gateway) is what actually exercises the modelled
        # relation; a ping test would "fail" on a correct configuration.
        systemd.services.dhcp-service-assert = {
          description = "Assert the DHCP lease and the allowed DNS service path";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          wants = [ "network.target" ];
          # NixOS units get a minimal PATH; name every tool the script uses so
          # the assertion cannot fail for a reason unrelated to the network.
          path = with pkgs; [
            bash
            coreutils
            gawk
            iproute2
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            set -u

            gw=""
            i=0
            while [ "$i" -lt 60 ]; do
              gw=$(ip -4 route show default | awk '/^default/ { print $3; exit }')
              [ -n "$gw" ] && break
              i=$((i + 1))
              sleep 1
            done

            if [ -z "$gw" ]; then
              echo "ASSERT FAIL: no DHCP default gateway on eth0" >&2
              exit 1
            fi
            echo "lease gateway: $gw"

            i=0
            while [ "$i" -lt 30 ]; do
              if timeout 3 bash -c "exec 3<>/dev/tcp/$gw/53" 2>/dev/null; then
                echo "ASSERT OK: allowed DNS service reachable at $gw:53"
                exit 0
              fi
              i=$((i + 1))
              sleep 1
            done

            echo "ASSERT FAIL: modelled DNS service unreachable at $gw:53" >&2
            exit 1
          '';
        };
      };
    };
  };
}
