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

  duplicateAddresses = lib.filter
    (address: lib.count (candidate: candidate == address) configuredAddresses > 1)
    (lib.unique configuredAddresses);

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

  qemuArgumentsFor = devices:
    lib.concatMap
      (device: [
        "-device"
        "vfio-pci,host=${device.pciAddress}"
      ])
      devices;

in
{
  options.local.virtualization.pciPassthrough = {
    enable = lib.mkEnableOption "runtime PCI passthrough for nixos-shell VMs";

    intelIommu = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Intel VT-d and passthrough-oriented IOMMU domains.";
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

    environment.systemPackages = [ passthrough ];

    services.nixosShellVmManager.instances = lib.mapAttrs
      (_: devices: {
        runner.qemuArguments = lib.mkAfter (qemuArgumentsFor devices);
      })
      devicesByVm;

    systemd.services = lib.mapAttrs'
      (vmName: devices:
        lib.nameValuePair "${vmName}-vm" {
          preStart = lib.mkBefore (lib.concatMapStringsSep "\n" bindCommand devices);
          postStop = lib.mkAfter (
            lib.concatMapStringsSep "\n" releaseCommand (lib.reverseList devices)
          );
        })
      devicesByVm;
  };
}
