{ startOnBootInstances ? [ "s-test" ] }:
{ config
, inputs
, lib
, pkgs
, relativeRepo
, self
, ...
}:
let
  prodInventory = import (relativeRepo.module "prod-network/current/inventory.nix");
  prodVlan3DnsRecords =
    prodInventory.realization.nodes."esp0xdeadbeef-site-a-access-vlan3".services.dns.localRecords;
  prodVlan3DnsRecord = builtins.head prodVlan3DnsRecords;
  prodVlan3DnsName = lib.removeSuffix "." prodVlan3DnsRecord.name;
  prodVlan3DnsIpv4 = builtins.head prodVlan3DnsRecord.a;

  guestAgentHealth =
    inputs.nixos-shell-vm-manager.packages.${pkgs.stdenv.hostPlatform.system}."qga-systemd-health";

  qgaSocketFor = vmName: "/run/nixos-shell-vm-manager/${vmName}/qga.sock";

  qgaHealthCommandFor =
    vmName:
    lib.escapeShellArgs [
      (lib.getExe guestAgentHealth)
      (qgaSocketFor vmName)
    ];

  qgaArgumentsFor = vmName: [
    "-chardev"
    "socket,id=qga0,path=${qgaSocketFor vmName},server=on,wait=off"
    "-device"
    "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"
  ];

  pinRefreshFlakeRef = "path:${inputs.pin-refresh-source}";

  routerCriticalUnits = [
    "systemd-networkd.service"
    "container@access-vlan2.service"
    "container@access-vlan3.service"
    "container@access-vlan7.service"
    "container@core.service"
    "container@downstream-selector.service"
    "container@policy.service"
    "container@upstream-selector.service"
  ];

  routerHealthCommand = ''
    status=0
    for unit in "$@"; do
      if state=$(/run/current-system/sw/bin/systemctl is-active "$unit" 2>&1); then
        :
      else
        status=1
      fi
      printf '%s=%s\n' "$unit" "$state"
    done

    if [[ "$status" -ne 0 ]]; then
      exit "$status"
    fi

    ip=/run/current-system/sw/bin/ip
    bash=/run/current-system/sw/bin/bash
    ping=/run/current-system/sw/bin/ping
    sleep=/run/current-system/sw/bin/sleep
    sysctl=/run/current-system/sw/bin/sysctl
    namespace=gamp-vlan2-health
    host_interface=gamp-v2-host
    client_interface=gamp-v2-client

    shopt -s nullglob
    mkdir_candidates=(/nix/store/*-coreutils-*/bin/mkdir)
    rm_candidates=(/nix/store/*-coreutils-*/bin/rm)
    mkdir_bin=''${mkdir_candidates[0]:-}
    rm_bin=''${rm_candidates[0]:-}

    [[ -x "$mkdir_bin" && -x "$rm_bin" ]]

    cleanup_vlan2_health() (
      set +e
      "$ip" netns del "$namespace" >/dev/null 2>&1
      "$ip" link del "$host_interface" >/dev/null 2>&1
      "$rm_bin" -rf -- "/etc/netns/$namespace"
    )

    trap cleanup_vlan2_health EXIT
    trap 'exit 1' HUP INT TERM
    cleanup_vlan2_health

    "$ip" netns add "$namespace"
    "$ip" netns exec "$namespace" "$sysctl" -q -w \
      net.ipv6.conf.all.disable_ipv6=0 \
      net.ipv6.conf.default.disable_ipv6=0 \
      net.ipv6.conf.all.forwarding=0 \
      net.ipv6.conf.default.accept_ra=2 \
      net.ipv6.conf.default.accept_ra_mtu=1
    "$ip" link add "$host_interface" type veth peer name "$client_interface"
    "$ip" link set "$host_interface" master lan2
    "$ip" link set "$host_interface" up
    "$ip" link set "$client_interface" netns "$namespace"
    "$ip" -n "$namespace" link set lo up
    "$ip" netns exec "$namespace" "$sysctl" -q -w \
      "net.ipv6.conf.$client_interface.disable_ipv6=0" \
      "net.ipv6.conf.$client_interface.accept_ra=2" \
      "net.ipv6.conf.$client_interface.accept_ra_mtu=1" \
      "net.ipv6.conf.$client_interface.autoconf=1"
    "$ip" -n "$namespace" link set "$client_interface" address 02:00:00:02:fe:01
    "$ip" -n "$namespace" link set "$client_interface" up
    "$ip" -n "$namespace" address add 192.168.1.254/24 dev "$client_interface"
    "$ip" -n "$namespace" route add default via 192.168.1.1

    vlan2_ipv6_ready=false
    for _ in {1..30}; do
      ipv6_mtu=$(
        "$ip" netns exec "$namespace" "$sysctl" -n \
          "net.ipv6.conf.$client_interface.mtu"
      )
      if [[ "$ipv6_mtu" == 1492 ]] \
        && "$ip" -n "$namespace" -6 route show default proto ra \
          | /run/current-system/sw/bin/grep -q '^default' \
        && "$ip" -n "$namespace" -6 address show \
          dev "$client_interface" scope global -tentative \
          | /run/current-system/sw/bin/grep -q 'inet6 '; then
        vlan2_ipv6_ready=true
        break
      fi
      "$sleep" 0.5
    done

    [[ "$vlan2_ipv6_ready" == true ]]

    "$mkdir_bin" -p "/etc/netns/$namespace"
    printf 'nameserver 192.168.1.1\noptions timeout:2 attempts:2\n' \
      >"/etc/netns/$namespace/resolv.conf"

    "$ip" netns exec "$namespace" "$bash" -c '
      vlan3_dns_seen=false
      while read -r address _; do
        [[ "$address" == ${prodVlan3DnsIpv4} ]] || exit 1
        vlan3_dns_seen=true
      done < <(
        /run/current-system/sw/bin/getent ahostsv4 ${prodVlan3DnsName}
      )
      [[ "$vlan3_dns_seen" == true ]]
      exec 3<>/dev/tcp/example.com/80 2>/dev/null || exit 1
      printf "HEAD / HTTP/1.0\r\nHost: example.com\r\nConnection: close\r\n\r\n" >&3
      IFS= read -r -t 10 status <&3 || exit 1
      [[ "$status" == HTTP/* ]]
    ' >/dev/null 2>&1

    "$ip" netns exec "$namespace" "$ping" -6 -n -q \
      -c 3 -W 2 -M do -s 1444 2606:4700:4700::1111 \
      >/dev/null 2>&1

    cleanup_vlan2_health
    trap - EXIT HUP INT TERM

    if "$ip" link show "$host_interface" >/dev/null 2>&1 \
      || "$ip" netns exec "$namespace" "$bash" -c : >/dev/null 2>&1 \
      || [[ -e "/etc/netns/$namespace" ]]; then
      exit 1
    fi

    printf 'vlan2-client=healthy\n'
  '';

  vms = [
    {
      name = "s-infra";
      description = "Infra VM (nixos-shell)";
    }
    {
      name = "s-nebula";
      description = "Nebula VM (nixos-shell)";
    }
    {
      name = "s-agents";
      description = "Agent workbench VM (nixos-shell)";
    }
    {
      name = "s-router-legacy-edge";
      description = "s-router-legacy-edge VM (nixos-shell)";
    }
    {
      name = "s-router-legacy-core";
      description = "s-router-core VM (nixos-shell)";
    }
    {
      name = "s-router-clab";
      description = "s-router-clab VM (nixos-shell)";
      activation.refreshPins = true;
    }
    {
      name = "s-router-nixos";
      description = "s-router-nixos VM (nixos-shell)";
      activation.refreshPins = true;
    }
    {
      name = "s-router-prod";
      description = "Production router canary VM (nixos-shell)";
      activation.rolloutCandidateOnGuestShutdown = true;
      healthCheck = {
        command = lib.escapeShellArgs (
          [
            (lib.getExe guestAgentHealth)
            (qgaSocketFor "s-router-prod")
            "/run/current-system/sw/bin/bash"
            "-c"
            routerHealthCommand
            "qga-systemd-health"
          ]
          ++ routerCriticalUnits
        );
        timeoutSeconds = 120;
        retries = 60;
        intervalSeconds = 3;
      };
    }
    {
      name = "s-router-legacy-prod";
      description = "Legacy production router fallback VM (nixos-shell)";
      runnerRelativePath = "bin/run-s-router-prod-vm";
    }
    {
      name = "s-router-test-clients";
      description = "s-router-test-clients VM (nixos-shell)";
      activation.refreshPins = true;
    }
    {
      name = "s-router-vpn-egress";
      description = "VPN-egress VM (nixos-shell)";
    }
    {
      name = "s-gameserver";
      description = "Gameserver VM (nixos-shell)";
    }
    {
      name = "s-test";
      description = "s-test (nixos-shell)";
    }
  ];

  vmNames = map (vm: vm.name) vms;
  unknownStartOnBootInstances = lib.subtractLists vmNames startOnBootInstances;

  mkInstance = vm: {
    inherit (vm) name;
    value = {
      inherit (vm) description;
      image = self.nixosConfigurations.${vm.name}.config.system.build.nixos-shell;
      activation = {
        startOnBoot = builtins.elem vm.name startOnBootInstances;
      }
      // (vm.activation or { });
      healthCheck = vm.healthCheck or {
        command = qgaHealthCommandFor vm.name;
        timeoutSeconds = 10;
        retries = 60;
        intervalSeconds = 2;
      };
      storage.persistentDisk = {
        enable = true;
        fileName = "state.qcow2";
        size = "100G";
      };
      runner = {
        stopGraceSeconds = 60;
        qemuArguments = qgaArgumentsFor vm.name ++ (vm.qemuArguments or [ ]);
      }
      // lib.optionalAttrs (vm ? runnerRelativePath)
        {
          relativePath = vm.runnerRelativePath;
        };
    }
    // lib.optionalAttrs (vm.activation.refreshPins or false) {
      pinRefresh = {
        flakeRef = pinRefreshFlakeRef;
        flakeAttribute = "nixosConfigurations.${vm.name}.config.system.build.nixos-shell";
      };
    };
  };
in
{
  assertions = [
    {
      assertion = unknownStartOnBootInstances == [ ];
      message = "Unknown nixos-shell start-on-boot instances: ${lib.concatStringsSep ", " unknownStartOnBootInstances}";
    }
  ];

  services.nixosShellVmManager = {
    enable = true;
    maxConcurrentBuilds = 1;
    persistentDirectory = "/persist/vm-persists";
    instances = lib.listToAttrs (map mkInstance vms);
  };

  system.build.vmImages = lib.mapAttrs (_: instance: instance.image) (
    lib.filterAttrs (_: instance: instance.enable) config.services.nixosShellVmManager.instances
  );
}
