{ config
, lib
, pkgs
, ...
}:

let
  cfg = config.local.virtualization.pciPassthrough;

  canonicalPciAddress = "[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\\.[0-7]";

  enabledDevices = lib.filterAttrs (_: device: device.enable) cfg.devices;
  deviceNames = lib.attrNames enabledDevices;
  configuredAddresses = map (name: enabledDevices.${name}.pciAddress) deviceNames;

  devicesByVm = lib.groupBy (device: device.vmName) (lib.attrValues enabledDevices);
  lateHotplugDevicesByVm = lib.filterAttrs
    (_: devices: devices != [ ])
    (lib.mapAttrs
      (_: devices: lib.filter (device: device.lateHotplug.enable) devices)
      devicesByVm);

  duplicateAddresses = lib.filter
    (address: lib.count (candidate: candidate == address) configuredAddresses > 1)
    (lib.unique configuredAddresses);

  rootPortId = device:
    "pci_hotplug_${lib.replaceStrings [ ":" "." ] [ "_" "_" ] device.pciAddress}";

  deviceId = device:
    "vfio_device_${lib.replaceStrings [ ":" "." ] [ "_" "_" ] device.pciAddress}";

  passthrough = pkgs.writeShellApplication {
    name = "pci-passthrough";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.kmod
      pkgs.util-linux
    ];
    text = ''
      set -euo pipefail

      usage() {
        echo "usage: pci-passthrough bind|release|status OWNER PCI_ADDRESS [EXPECTED_GROUP_MEMBER ...]" >&2
        exit 64
      }

      [[ $# -ge 3 ]] || usage
      action=$1
      owner=$2
      address=$3
      shift 3

      [[ "$owner" =~ ^[A-Za-z0-9._@-]+$ ]] || {
        echo "invalid passthrough owner: $owner" >&2
        exit 64
      }
      [[ "$address" =~ ^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]$ ]] || {
        echo "PCI address must be canonical lowercase domain:bus:slot.function: $address" >&2
        exit 64
      }

      device=/sys/bus/pci/devices/$address
      state_dir=/run/pci-passthrough
      state_file=$state_dir/$address.state
      lock_file=/run/lock/pci-passthrough-$address.lock

      mkdir -p "$state_dir"
      exec 9>"$lock_file"
      flock -x 9

      [[ -d "$device" ]] || {
        echo "PCI device does not exist: $address" >&2
        exit 69
      }

      current_driver() {
        if [[ -L "$device/driver" ]]; then
          basename "$(readlink -f "$device/driver")"
        else
          echo none
        fi
      }

      bind_in_progress=false
      previous_driver=none

      rollback_failed_bind() {
        exit_status=$?
        trap - EXIT

        if [[ "$bind_in_progress" == true && "$exit_status" -ne 0 ]]; then
          set +e
          rm -f "$state_file.tmp"

          if [[ "$previous_driver" != vfio-pci && "$(current_driver)" == vfio-pci ]]; then
            echo "$address" > "$device/driver/unbind"
          fi
          echo > "$device/driver_override"

          if [[ "$previous_driver" != none && "$previous_driver" != vfio-pci ]]; then
            modprobe "$previous_driver"
            echo "$address" > /sys/bus/pci/drivers_probe
          fi

          if [[ "$(current_driver)" != "$previous_driver" ]]; then
            echo "warning: failed to restore $address to $previous_driver after bind failure" >&2
          fi
        fi

        exit "$exit_status"
      }

      trap rollback_failed_bind EXIT

      validate_iommu_group() {
        [[ -L "$device/iommu_group" ]] || {
          echo "PCI device $address has no IOMMU group; reboot with IOMMU enabled" >&2
          exit 78
        }

        group_path=$(readlink -f "$device/iommu_group")
        mapfile -t actual_members < <(
          find "$group_path/devices" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
        )
        mapfile -t expected_members < <(printf '%s\n' "$address" "$@" | sort -u)

        if [[ "''${actual_members[*]}" != "''${expected_members[*]}" ]]; then
          echo "IOMMU group for $address differs from the declared group" >&2
          echo "declared: ''${expected_members[*]}" >&2
          echo "actual:   ''${actual_members[*]}" >&2
          exit 78
        fi
      }

      case "$action" in
        bind)
          validate_iommu_group "$@"

          if [[ -e "$state_file" ]]; then
            read -r recorded_owner previous_driver < "$state_file"
            if [[ "$recorded_owner" == "$owner" && "$(current_driver)" == vfio-pci ]]; then
              exit 0
            fi
            echo "PCI device $address is already owned by $recorded_owner" >&2
            exit 73
          fi

          previous_driver=$(current_driver)
          bind_in_progress=true
          modprobe vfio-pci
          echo vfio-pci > "$device/driver_override"

          if [[ "$previous_driver" != none && "$previous_driver" != vfio-pci ]]; then
            echo "$address" > "$device/driver/unbind"
          fi

          if [[ "$(current_driver)" != vfio-pci ]]; then
            echo "$address" > /sys/bus/pci/drivers_probe
          fi

          if [[ "$(current_driver)" != vfio-pci ]]; then
            echo "failed to bind $address to vfio-pci" >&2
            exit 70
          fi

          printf '%s %s\n' "$owner" "$previous_driver" > "$state_file.tmp"
          mv "$state_file.tmp" "$state_file"
          bind_in_progress=false
          ;;

        release)
          if [[ ! -e "$state_file" ]]; then
            echo > "$device/driver_override"
            exit 0
          fi

          read -r recorded_owner previous_driver < "$state_file"
          if [[ "$recorded_owner" != "$owner" ]]; then
            echo "refusing to release $address owned by $recorded_owner" >&2
            exit 73
          fi

          if [[ "$(current_driver)" == vfio-pci ]]; then
            echo "$address" > "$device/driver/unbind"
          fi
          echo > "$device/driver_override"

          restore_driver=''${1:-false}
          if [[ "$restore_driver" == true && "$previous_driver" != none && "$previous_driver" != vfio-pci ]]; then
            modprobe "$previous_driver"
            echo "$address" > /sys/bus/pci/drivers_probe
            if [[ "$(current_driver)" != "$previous_driver" ]]; then
              echo "failed to restore $address to $previous_driver" >&2
              exit 70
            fi
          fi

          rm -f "$state_file"
          ;;

        status)
          printf 'address=%s\n' "$address"
          printf 'driver=%s\n' "$(current_driver)"
          if [[ -L "$device/iommu_group" ]]; then
            printf 'iommu_group=%s\n' "$(basename "$(readlink -f "$device/iommu_group")")"
          else
            printf 'iommu_group=none\n'
          fi
          if [[ -e "$state_file" ]]; then
            read -r recorded_owner previous_driver < "$state_file"
            printf 'owner=%s\n' "$recorded_owner"
            printf 'previous_driver=%s\n' "$previous_driver"
          else
            printf 'owner=none\n'
          fi
          ;;

        *)
          usage
          ;;
      esac
    '';
  };

  qmpHotplug = pkgs.writeShellApplication {
    name = "pci-passthrough-qmp-hotplug";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.socat
    ];
    text = ''
      set -euo pipefail

      if [[ $# -ne 4 ]]; then
        echo "usage: pci-passthrough-qmp-hotplug QMP_SOCKET PCI_ADDRESS ROOT_PORT_ID DEVICE_ID" >&2
        exit 64
      fi

      qmp_socket=$1
      pci_address=$2
      root_port_id=$3
      device_id=$4

      [[ -S "$qmp_socket" ]] || {
        echo "QMP socket does not exist: $qmp_socket" >&2
        exit 69
      }
      [[ "$pci_address" =~ ^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]$ ]] || {
        echo "invalid canonical PCI address: $pci_address" >&2
        exit 64
      }
      [[ "$root_port_id" =~ ^[A-Za-z0-9._-]+$ ]] || {
        echo "invalid QEMU root port ID: $root_port_id" >&2
        exit 64
      }
      [[ "$device_id" =~ ^[A-Za-z0-9._-]+$ ]] || {
        echo "invalid QEMU device ID: $device_id" >&2
        exit 64
      }

      qmp_exchange() {
        timeout 15 socat - "UNIX-CONNECT:$qmp_socket"
      }

      existing_response=$(
        printf '%s\n%s\n' \
          '{"execute":"qmp_capabilities"}' \
          '{"execute":"query-pci"}' \
          | qmp_exchange
      )

      if jq -s -e --arg device_id "$device_id" \
        '[.. | objects | select(.qdev_id? == $device_id)] | length > 0' \
        <<< "$existing_response" >/dev/null; then
        exit 0
      fi

      device_add_request=$(
        jq -cn \
          --arg host "$pci_address" \
          --arg bus "$root_port_id" \
          --arg id "$device_id" \
          '{
            execute: "device_add",
            arguments: {
              driver: "vfio-pci",
              host: $host,
              bus: $bus,
              id: $id
            }
          }'
      )

      hotplug_response=$(
        printf '%s\n%s\n' \
          '{"execute":"qmp_capabilities"}' \
          "$device_add_request" \
          | qmp_exchange
      )

      if jq -s -e 'any(.[]; has("error"))' <<< "$hotplug_response" >/dev/null; then
        jq -c 'select(has("error"))' <<< "$hotplug_response" >&2
        exit 70
      fi
    '';
  };

  bindCommand = device:
    lib.escapeShellArgs (
      [
        (lib.getExe passthrough)
        "bind"
        device.vmName
        device.pciAddress
      ]
      ++ device.iommuGroupMembers
    );

  releaseCommand = device:
    lib.escapeShellArgs [
      (lib.getExe passthrough)
      "release"
      device.vmName
      device.pciAddress
      (lib.boolToString device.restoreDriverOnStop)
    ];

  qemuArgumentsFor =
    vmName: devices:
    let
      hasLateHotplug = lib.any (device: device.lateHotplug.enable) devices;
      readySocket = "/run/nixos-shell-vm-manager/${vmName}/pci-ready.sock";
    in
    lib.optionals hasLateHotplug [
      "-device"
      "virtio-serial-pci,id=pci_hotplug_signal_bus"
      "-chardev"
      "socket,id=pci_hotplug_signal,path=${readySocket},reconnect-ms=250"
      "-device"
      "virtserialport,bus=pci_hotplug_signal_bus.0,chardev=pci_hotplug_signal,name=org.nixos.pci-ready.0"
    ]
    ++ lib.concatLists (
      lib.imap0
        (index: device:
        if device.lateHotplug.enable then
          [
            "-device"
            (lib.concatStringsSep "," (
              [
                "pcie-root-port"
                "id=${rootPortId device}"
                "chassis=${toString (index + 1)}"
                "slot=${toString (index + 1)}"
              ]
              ++ lib.optional (device.lateHotplug.memoryReserve != null)
                "mem-reserve=${device.lateHotplug.memoryReserve}"
              ++ lib.optional (device.lateHotplug.prefetchableMemoryReserve != null)
                "pref64-reserve=${device.lateHotplug.prefetchableMemoryReserve}"
            ))
          ]
        else
          [
            "-device"
            "vfio-pci,host=${device.pciAddress}"
          ])
        devices
    );

  hotplugServiceScript =
    vmName: devices:
    let
      controlDirectory = "/run/nixos-shell-vm-manager/${vmName}";
      qmpSocket = "${controlDirectory}/qmp.sock";
      readySocket = "${controlDirectory}/pci-ready.sock";
      hotplugCommands = lib.concatMapStringsSep "\n"
        (device:
          lib.escapeShellArgs [
            (lib.getExe qmpHotplug)
            qmpSocket
            device.pciAddress
            (rootPortId device)
            (deviceId device)
          ])
        devices;
    in
    ''
      qmp_identity=
      while [[ -z "$qmp_identity" ]]; do
        qmp_identity=$(
          ${pkgs.coreutils}/bin/stat -Lc '%d:%i' ${lib.escapeShellArg qmpSocket} 2>/dev/null \
            || true
        )
        if [[ -z "$qmp_identity" ]]; then
          ${pkgs.coreutils}/bin/sleep 0.25
        fi
      done

      ready_pid=
      cleanup_ready_listener() {
        if [[ -n "$ready_pid" ]] && kill -0 "$ready_pid" 2>/dev/null; then
          kill "$ready_pid"
          wait "$ready_pid" 2>/dev/null || true
        fi
      }
      trap cleanup_ready_listener EXIT

      ${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg readySocket}
      coproc READY_CHANNEL {
        exec ${pkgs.socat}/bin/socat \
          UNIX-LISTEN:${lib.escapeShellArg readySocket},unlink-close \
          -
      }
      ready_pid=$READY_CHANNEL_PID
      ready_fd=''${READY_CHANNEL[0]}

      ready_message=
      if ! IFS= read -r -t 300 -u "$ready_fd" ready_message; then
        echo "timed out waiting for guest kernel readiness: ${vmName}" >&2
        exit 1
      fi
      if [[ "$ready_message" != pci-ready ]]; then
        echo "guest did not signal kernel readiness for PCI hotplug: ${vmName}" >&2
        exit 1
      fi

      current_identity=$(
        ${pkgs.coreutils}/bin/stat -Lc '%d:%i' ${lib.escapeShellArg qmpSocket} 2>/dev/null \
          || true
      )
      if [[ "$current_identity" != "$qmp_identity" ]]; then
        echo "QMP socket changed while waiting for guest kernel readiness: ${vmName}" >&2
        exit 1
      fi

      ${hotplugCommands}

      while [[ "$(
        ${pkgs.coreutils}/bin/stat -Lc '%d:%i' ${lib.escapeShellArg qmpSocket} 2>/dev/null \
          || true
      )" == "$qmp_identity" ]]; do
        ${pkgs.coreutils}/bin/sleep 0.5
      done
    '';

in
{
  options.local.virtualization.pciPassthrough = {
    enable = lib.mkEnableOption "runtime PCI passthrough for nixos-shell VMs";

    intelIommu = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Intel VT-d and passthrough-oriented IOMMU domains.";
    };

    dmaEntryLimit = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      example = 1048576;
      description = ''
        Maximum number of simultaneous VFIO type1 DMA mappings per
        container. Increase this for guests whose vIOMMU produces many
        small mappings.
      '';
    };

    devices = lib.mkOption {
      default = { };
      description = "PCI devices assigned exclusively to nixos-shell VM services.";
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "this PCI passthrough device" // {
            default = true;
          };

          pciAddress = lib.mkOption {
            type = lib.types.strMatching canonicalPciAddress;
            example = "0000:03:00.0";
            description = "Stable canonical PCI address on the VM host.";
          };

          vmName = lib.mkOption {
            type = lib.types.strMatching "[A-Za-z0-9._@-]+";
            example = "s-llm-inference";
            description = "nixos-shell VM instance that exclusively owns the device while running.";
          };

          iommuGroupMembers = lib.mkOption {
            type = lib.types.listOf (lib.types.strMatching canonicalPciAddress);
            default = [ ];
            description = ''
              Other PCI functions expected in the same IOMMU group. Every
              declared member must be assigned to the same VM. The device's
              own address is included automatically.
            '';
          };

          restoreDriverOnStop = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Reprobe the driver that owned the device before the VM started.";
          };

          lateHotplug = {
            enable = lib.mkEnableOption "QMP hotplug after the guest kernel signals readiness";

            memoryReserve = lib.mkOption {
              type = lib.types.nullOr (lib.types.strMatching "[0-9]+[KMGT]?");
              default = null;
              example = "32M";
              description = "Non-prefetchable MMIO reserved on the hotplug root port.";
            };

            prefetchableMemoryReserve = lib.mkOption {
              type = lib.types.nullOr (lib.types.strMatching "[0-9]+[KMGT]?");
              default = null;
              example = "32G";
              description = "64-bit prefetchable MMIO reserved on the hotplug root port.";
            };
          };
        };
      });
    };

  };

  config = lib.mkIf cfg.enable {
    assertions =
      [
        {
          assertion = enabledDevices != { };
          message = "PCI passthrough is enabled without any enabled devices.";
        }
        {
          assertion = duplicateAddresses == [ ];
          message = "PCI passthrough addresses must be unique: ${lib.concatStringsSep ", " duplicateAddresses}";
        }
        {
          assertion = lib.all
            (devices: lib.length devices <= 255)
            (lib.attrValues lateHotplugDevicesByVm);
          message = "A VM cannot have more than 255 late-hotplug PCI root ports.";
        }
      ]
      ++ lib.concatMap
        (name:
          let
            device = enabledDevices.${name};
            groupMembers = map
              (address: lib.findFirst
                (candidate: candidate.pciAddress == address)
                null
                (lib.attrValues enabledDevices))
              device.iommuGroupMembers;
          in
          [
            {
              assertion = lib.all (member: member != null && member.vmName == device.vmName) groupMembers;
              message = "Every IOMMU peer declared for ${name} must be assigned to VM ${device.vmName}.";
            }
            {
              assertion = !(lib.elem device.pciAddress device.iommuGroupMembers)
              && lib.length device.iommuGroupMembers == lib.length (lib.unique device.iommuGroupMembers);
              message = "IOMMU peers for ${name} must be unique and must not include the device itself.";
            }
            {
              assertion = lib.all
                (member:
                  member == null
                  || lib.sort builtins.lessThan ([ member.pciAddress ] ++ member.iommuGroupMembers)
                  == lib.sort builtins.lessThan ([ device.pciAddress ] ++ device.iommuGroupMembers))
                groupMembers;
              message = "Every IOMMU peer declaration for ${name} must describe the same complete group.";
            }
          ])
        deviceNames;

    boot.kernelParams = lib.optionals cfg.intelIommu [
      "intel_iommu=on"
      "iommu=pt"
    ];

    boot.extraModprobeConfig = lib.optionalString (cfg.dmaEntryLimit != null) ''
      options vfio_iommu_type1 dma_entry_limit=${toString cfg.dmaEntryLimit}
    '';

    environment.systemPackages = [ passthrough ];

    services.nixosShellVmManager.instances = lib.mapAttrs
      (vmName: devices: {
        runner.qemuArguments = lib.mkAfter (qemuArgumentsFor vmName devices);
      })
      devicesByVm;

    systemd.services = lib.mkMerge [
      (lib.mapAttrs'
        (vmName: devices:
          lib.nameValuePair "${vmName}-pci-bind" {
            description = "Bind PCI devices for ${vmName}";
            wantedBy = [ "multi-user.target" ];
            before = [ "${vmName}-vm.service" ];
            partOf = [ "${vmName}-vm.service" ];
            script = lib.concatMapStringsSep "\n" bindCommand devices;
            preStop = lib.concatMapStringsSep "\n" releaseCommand (lib.reverseList devices);
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
          })
        devicesByVm)

      (lib.mapAttrs'
        (vmName: _devices:
          lib.nameValuePair "${vmName}-vm" {
            after = [ "${vmName}-pci-bind.service" ];
            requires = [ "${vmName}-pci-bind.service" ];
            wants = lib.optional (builtins.hasAttr vmName lateHotplugDevicesByVm)
              "${vmName}-pci-hotplug.service";
          })
        devicesByVm)

      (lib.mapAttrs'
        (vmName: devices:
          lib.nameValuePair "${vmName}-pci-hotplug" {
            description = "Late PCI hotplug for ${vmName}";
            after = [ "${vmName}-vm.service" ];
            requires = [ "${vmName}-vm.service" ];
            partOf = [ "${vmName}-vm.service" ];
            script = hotplugServiceScript vmName devices;
            serviceConfig = {
              Type = "simple";
              Restart = "always";
              RestartSec = "2s";
            };
          })
        lateHotplugDevicesByVm)
    ];
  };
}
