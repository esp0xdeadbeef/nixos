{ config
, lib
, pkgs
, ...
}:

let
  cfg = config.local.virtualization.pciPassthroughGuest;
  readyPort = "/dev/virtio-ports/org.nixos.pci-ready.0";
in
{
  options.local.virtualization.pciPassthroughGuest.enable =
    lib.mkEnableOption "an Intel vIOMMU for late-hotplugged PCI devices";

  config = lib.mkIf cfg.enable {
    boot.kernelParams = [ "intel_iommu=on" ];

    boot.initrd = {
      kernelModules = [ "virtio_console" ];
      systemd = {
        enable = true;
        services.pci-passthrough-ready = {
          description = "Signal that the guest kernel is ready for PCI hotplug";
          wantedBy = [ "initrd.target" ];
          after = [
            "systemd-udevd.service"
            "systemd-udev-trigger.service"
          ];
          before = [ "initrd-switch-root.target" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig.Type = "oneshot";
          script = ''
            for _attempt in $(${pkgs.coreutils}/bin/seq 1 200); do
              if [[ -c ${readyPort} ]]; then
                echo pci-ready > ${readyPort}
                exit 0
              fi
              ${pkgs.coreutils}/bin/sleep 0.05
            done

            echo "PCI hotplug readiness port did not appear: ${readyPort}" >&2
            exit 1
          '';
        };
      };
    };

    virtualisation.qemu.options = lib.mkAfter [
      "-machine q35,kernel-irqchip=split"
      "-cpu host"
      "-device intel-iommu,caching-mode=on,intremap=on"
    ];
  };
}
