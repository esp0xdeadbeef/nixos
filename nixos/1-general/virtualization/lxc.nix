{ config, pkgs, ... }:
{
  users.groups.lxc-user = {
    members = [ "deadbeef" ];
  };

  virtualisation.lxc = {
    enable = true;
    unprivilegedContainers = true;

    defaultConfig = ''
      lxc.net.0.type = veth
      lxc.net.0.link = lxcbr0
      lxc.net.0.flags = up
      ##lxc.net.0.hwaddr = 00:16:3e:11:22:33
      lxc.apparmor.profile = generated
      lxc.apparmor.allow_nesting = 1
      lxc.idmap = u 0 100000 65535
      lxc.idmap = g 0 100000 65535
    '';
    usernetConfig = ''
      deadbeef veth lxcbr0 10
    '';
    lxcfs.enable = true;
  };

  system.activationScripts.setLxcHomeACL = {
    text = ''
      export PATH=${pkgs.acl}/bin:$PATH
      mkdir -p /home/deadbeef/.config/lxc/
      cp /etc/lxc/default.conf /home/deadbeef/.config/lxc/default.conf
      chown deadbeef:users /home/deadbeef/.config
      chown deadbeef:users /home/deadbeef/.config/lxc
      chown deadbeef:users /home/deadbeef/.config/lxc/default.conf
      setfacl -m u:100000:--x /home/deadbeef
      setfacl -m u:100000:--x /home/deadbeef/.local
      setfacl -m u:100000:--x /home/deadbeef/.local/share/
      setfacl -m u:100000:--x /home/deadbeef/.local/share/lxc
    '';
  };

  # 🔥 This script will forcibly kill any UID 1000 LXC containers
  environment.etc."nuke-lxc-from-orbit-on-shutdown.sh" = {
    text = ''
      #!${pkgs.bash}/bin/bash

      ${pkgs.util-linux}/bin/mount | grep rootfs/mnt | ${pkgs.gawk}/bin/awk '{print $3}' | while read line ; do
        ${pkgs.procps}/bin/ps -ef | ${pkgs.gnugrep}/bin/grep "^100[0-9][0-9][0-9]" | ${pkgs.coreutils}/bin/tr -s " " | ${pkgs.coreutils}/bin/cut -f2 -d " " | ${pkgs.findutils}/bin/xargs -r ${pkgs.coreutils}/bin/kill -9
        while ${pkgs.util-linux}/bin/umount "$line"; do :; done
      done

      ${pkgs.procps}/bin/ps -ef | ${pkgs.gnugrep}/bin/grep "^100[0-9][0-9][0-9]" | ${pkgs.coreutils}/bin/tr -s " " | ${pkgs.coreutils}/bin/cut -f2 -d " " | ${pkgs.findutils}/bin/xargs -r ${pkgs.coreutils}/bin/kill -9
    '';
    mode = "0755";
  };

  # ✅ Clean way to override reboot/poweroff/halt in systemd
  systemd.services.reboot = {
    overrideStrategy = "asDropin";
    serviceConfig.ExecStartPre = [ "/etc/nuke-lxc-from-orbit-on-shutdown.sh" ];
  };

  systemd.services.poweroff = {
    overrideStrategy = "asDropin";
    serviceConfig.ExecStartPre = [ "/etc/nuke-lxc-from-orbit-on-shutdown.sh" ];
  };

  systemd.services.halt = {
    overrideStrategy = "asDropin";
    serviceConfig.ExecStartPre = [ "/etc/nuke-lxc-from-orbit-on-shutdown.sh" ];
  };

  # 🧨 Emergency kill service tied to shutdown/reboot/halt
  systemd.services.nuke-before-anything = {
    description = "Run BEFORE reboot, poweroff, shutdown, halt";
    before = [
      "reboot.target"
      "poweroff.target"
      "halt.target"
      "shutdown.target"
    ];
    wantedBy = [
      "reboot.target"
      "poweroff.target"
      "halt.target"
      "shutdown.target"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/etc/nuke-lxc-from-orbit-on-shutdown.sh";
      TimeoutSec = 60;
      RemainAfterExit = true;
    };
  };

  # 🧰 Extra convenience: override CLI shutdown commands (userspace)
  environment.systemPackages = with pkgs; [
    bindfs
    skopeo
    umoci

    (writeShellScriptBin "reboot" ''
      /etc/nuke-lxc-from-orbit-on-shutdown.sh
      exec ${pkgs.systemd}/bin/reboot "$@"
    '')

    (writeShellScriptBin "poweroff" ''
      /etc/nuke-lxc-from-orbit-on-shutdown.sh
      exec ${pkgs.systemd}/bin/poweroff "$@"
    '')

    (writeShellScriptBin "shutdown" ''
      /etc/nuke-lxc-from-orbit-on-shutdown.sh
      exec ${pkgs.systemd}/bin/shutdown "$@"
    '')
  ];
}
