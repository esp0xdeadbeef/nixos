{
  config,
  pkgs,
  lib,
  ...
}:
let
  normalUserNames = lib.attrNames (
    lib.filterAttrs (_: u: u.isNormalUser or false) config.users.users
  );
  homeDirs = map (n: (config.users.users.${n}.home or "/home/${n}")) normalUserNames;
  homeDirsStr = lib.escapeShellArgs homeDirs;
  usernetLines = lib.concatStringsSep "\n" (map (u: "${u} veth lxcbr0 10") normalUserNames) + "\n"; # final newline keeps lxc quiet
in
{
  users.groups.lxc-user.members = normalUserNames;

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

      # # didn't work as expected (got g and uid 1000 inside container):
      # # UID map: allow podman user inside container to work
      # lxc.idmap = u 0 100000 1000
      # lxc.idmap = g 0 100000 1000
      # lxc.idmap = u 1000 1000 1
      # lxc.idmap = g 1000 1000 1
      # lxc.idmap = u 1001 101001 64534
      # lxc.idmap = g 1001 101001 64534

      # new, include common and userns:
      lxc.include = /run/current-system/sw/share/lxc/config/common.conf
      lxc.include = /run/current-system/sw/share/lxc/config/userns.conf

      # enable network inside container(s):
      lxc.net.0.type = veth
      lxc.net.0.link = lxcbr0
      lxc.net.0.flags = up

      # allow tun to be used in the lxc container:
      lxc.cgroup.devices.allow = c 10:200 rwm
      lxc.mount.entry = /dev/net dev/net none bind,create=dir 0 0
    '';
    usernetConfig = usernetLines;
    lxcfs.enable = true;
    # doesn't work research needed:
    bridgeConfig = ''
      USE_LXC_BRIDGE="true"
      LXC_BRIDGE="lxcbr0"
      LXC_DHCP_CONFILE="/etc/lxc/dnsmasq.conf"
      LXC_DOMAIN="lxc-net.local"
      dhcp-host=osep-lxc,10.0.3.100
    '';
  };

  # doesn't work, research needed:
  environment.etc."lxc/dnsmasq.conf".text = ''
    dhcp-host=osep-lxc,10.0.3.100
  '';

  system.activationScripts.setLxcHomeACL.text = ''
    export PATH=${pkgs.acl}/bin:$PATH
    for home in ${homeDirsStr}; do
      user=$(basename "$home")                   # works even with /srv/users/alice
      echo "$user" | tee /tmp/test
      ls "$home" > /dev/null || exit             # die loudly if home missing
      mkdir -p "$home/.config/lxc" || exit
      cp /etc/lxc/default.conf "$home/.config/lxc/default.conf"
      chown "$user":users "$home/.config" "$home/.config/lxc" \
                    "$home/.config/lxc/default.conf"

      # give the user-namespace UID 100000 execute perms
      setfacl -m u:100000:--x "$home"
      setfacl -m u:100000:--x "$home/.local"
      setfacl -m u:100000:--x "$home/.local/share/"
      setfacl -m u:100000:--x "$home/.local/share/lxc"
    done
  '';

  environment.etc."nuke-lxc-from-orbit-on-shutdown.sh" = {
    text = ''
      #!${pkgs.bash}/bin/bash
      for home in ${homeDirsStr}; 
      do
        while sudo /run/current-system/sw/bin/umount $home/.local/share/lxc/osep-lxc/rootfs/mnt ; do :; done
        ${pkgs.util-linux}/bin/mount | grep rootfs/mnt | ${pkgs.gawk}/bin/awk '{print $3}' | while read line ; do
          ${pkgs.procps}/bin/ps -ef | ${pkgs.gnugrep}/bin/grep "^100[0-9][0-9][0-9]" | ${pkgs.coreutils}/bin/tr -s " " | ${pkgs.coreutils}/bin/cut -f2 -d " " | ${pkgs.findutils}/bin/xargs -r ${pkgs.coreutils}/bin/kill -9
          while sudo /run/current-system/sw/bin/umount $home/.local/share/lxc/osep-lxc/rootfs/mnt ; do :; done
        done

        ${pkgs.procps}/bin/ps -ef | ${pkgs.gnugrep}/bin/grep "^100[0-9][0-9][0-9]" | ${pkgs.coreutils}/bin/tr -s " " | ${pkgs.coreutils}/bin/cut -f2 -d " " | ${pkgs.findutils}/bin/xargs -r ${pkgs.coreutils}/bin/kill -9
      done
    '';
    mode = "0755";
  };


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
