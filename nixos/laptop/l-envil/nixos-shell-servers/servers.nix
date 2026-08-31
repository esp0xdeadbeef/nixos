{ inputs
, lib
, pkgs
, self
, ...
}:
let
  guestAgentHealth =
    inputs.nixos-shell-vm-manager.packages.${pkgs.stdenv.hostPlatform.system}."qga-systemd-health";
  qgaSocket = "/run/nixos-shell-vm-manager/s-router-cobalt/qga.sock";
  tangQgaSocket = "/run/nixos-shell-vm-manager/s-tang/qga.sock";
  apQgaSocket = "/run/nixos-shell-vm-manager/s-ap-nighthawk/qga.sock";
  alfaQgaSocket = "/run/nixos-shell-vm-manager/s-ap-alfa/qga.sock";
  nebulaQgaSocket = "/run/nixos-shell-vm-manager/s-nebula-cobalt/qga.sock";
in
{
  services.nixosShellVmManager = {
    enable = true;
    maxConcurrentBuilds = 1;
    persistentDirectory = "/persist/vm-persists";

    instances.s-router-cobalt = {
      description = "cobalt site router (nixos-shell)";
      image = self.nixosConfigurations.s-router-cobalt.config.system.build.nixos-shell;
      activation.startOnBoot = true;
      healthCheck = {
        command = lib.escapeShellArgs [
          (lib.getExe guestAgentHealth)
          qgaSocket
        ];
        timeoutSeconds = 10;
        retries = 60;
        intervalSeconds = 2;
      };
      runner.qemuArguments = [
        "-chardev"
        "socket,id=qga0,path=${qgaSocket},server=on,wait=off"
        "-device"
        "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"
      ];
      storage.persistentDisk = {
        enable = true;
        fileName = "state.qcow2";
        size = "20G";
      };
      runner.stopGraceSeconds = 60;
    };

    instances.s-nebula-cobalt = {
      description = "cobalt nebula lighthouse (nixos-shell)";
      image = self.nixosConfigurations.s-nebula-cobalt.config.system.build.nixos-shell;
      activation.startOnBoot = true;
      healthCheck = {
        command = lib.escapeShellArgs [
          (lib.getExe guestAgentHealth)
          nebulaQgaSocket
        ];
        timeoutSeconds = 10;
        retries = 60;
        intervalSeconds = 2;
      };
      runner.qemuArguments = [
        "-chardev"
        "socket,id=qga0,path=${nebulaQgaSocket},server=on,wait=off"
        "-device"
        "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"
      ];
      storage.persistentDisk = {
        enable = true;
        fileName = "state.qcow2";
        size = "4G";
      };
      runner.stopGraceSeconds = 30;
    };

    instances.s-tang = {
      description = "cobalt Tang (NBDE) server";
      image = self.nixosConfigurations.s-tang.config.system.build.nixos-shell;
      activation.startOnBoot = true;
      healthCheck = {
        command = lib.escapeShellArgs [
          (lib.getExe guestAgentHealth)
          tangQgaSocket
        ];
        timeoutSeconds = 10;
        retries = 60;
        intervalSeconds = 2;
      };
      runner.qemuArguments = [
        "-chardev"
        "socket,id=qga0,path=${tangQgaSocket},server=on,wait=off"
        "-device"
        "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"
        # Drop the nixos-shell default user-mode NAT NIC; the Tang host only
        # needs the cobalt trunk (mgmt VLAN 10 + unlock VLAN 90).
        "-net"
        "none"
        "-nic"
        "bridge,br=br-cobalt-lan,model=virtio-net-pci"
      ];
      runner.stopGraceSeconds = 30;
    };

    instances.s-ap-nighthawk = {
      description = "cobalt Nighthawk AP (mt7925u) on the cobalt trunk";
      image = self.nixosConfigurations.s-ap-nighthawk.config.system.build.nixos-shell;
      activation.startOnBoot = true;
      healthCheck = {
        command = lib.escapeShellArgs [
          (lib.getExe guestAgentHealth)
          apQgaSocket
        ];
        timeoutSeconds = 10;
        retries = 60;
        intervalSeconds = 2;
      };
      runner.qemuArguments = [
        "-chardev"
        "socket,id=qga0,path=${apQgaSocket},server=on,wait=off"
        "-device"
        "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"
        "-usb"
        "-device"
        "qemu-xhci,id=xhci"
        "-device"
        "usb-host,vendorid=0x0846,productid=0x9072,bus=xhci.0"
      ];
      runner.stopGraceSeconds = 30;
    };

    instances.s-ap-alfa = {
      description = "cobalt ALFA 2.4GHz AP (rt2800usb) on the cobalt trunk";
      image = self.nixosConfigurations.s-ap-alfa.config.system.build.nixos-shell;
      activation.startOnBoot = true;
      healthCheck = {
        command = lib.escapeShellArgs [
          (lib.getExe guestAgentHealth)
          alfaQgaSocket
        ];
        timeoutSeconds = 10;
        retries = 60;
        intervalSeconds = 2;
      };
      runner.qemuArguments = [
        "-chardev"
        "socket,id=qga0,path=${alfaQgaSocket},server=on,wait=off"
        "-device"
        "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"
        "-usb"
        "-device"
        "qemu-xhci,id=xhci"
        "-device"
        "usb-host,vendorid=0x148f,productid=0x3070,bus=xhci.0"
      ];
      runner.stopGraceSeconds = 30;
    };
  };
}
