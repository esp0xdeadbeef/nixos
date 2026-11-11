{ config
, pkgs
, lib
, ...
}:
let
  normalUserNames = lib.attrNames (
    lib.filterAttrs (_: u: u.isNormalUser or false) config.users.users
  );
  homeDirs = map (n: (config.users.users.${n}.home or "/home/${n}")) normalUserNames;
  homeDirsStr = lib.escapeShellArgs homeDirs;
  usernetLines = lib.concatStringsSep "\n" (map (u: "${u} veth lxcbr0 10") normalUserNames) + "\n"; # final newline keeps lxc quiet

  # The bindfs mounts that containers need a view of. The sudoers NOPASSWD rule
  # and the systemd unit that performs the mount are both generated from this
  # list, so the argv sudo is asked to authorise and the argv that is executed
  # cannot drift apart (a drift silently turns into a password prompt, then a
  # failed mount, then an endless restart loop).
  bindMounts = config.local.containerNetwork.bindMounts;

  bindfsFor = m: "${pkgs.bindfs}/bin/bindfs --uid-offset=${toString m.uidOffset} --gid-offset=${toString m.gidOffset} ${m.source} ${m.target}";
in
{
  options.local.containerNetwork.bindMounts = lib.mkOption {
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          source = lib.mkOption {
            type = lib.types.str;
            description = "Host directory to expose to the container.";
          };
          target = lib.mkOption {
            type = lib.types.str;
            description = "Mount point inside the container rootfs.";
          };
          uidOffset = lib.mkOption {
            type = lib.types.int;
            default = 100000;
            description = "UID offset applied by bindfs (matches the LXC idmap).";
          };
          gidOffset = lib.mkOption {
            type = lib.types.int;
            default = 100000;
            description = "GID offset applied by bindfs (matches the LXC idmap).";
          };
          user = lib.mkOption {
            type = lib.types.str;
            description = "User allowed to mount/unmount this share without a password.";
          };
          container = lib.mkOption {
            type = lib.types.str;
            description = ''
              Container name, used by the shutdown cleanup script. Only shares
              of this container are torn down there.
            '';
          };
        };
      }
    );
    default = [ ];
    description = ''
      bindfs shares that unprivileged containers mount from their rootfs. The
      sudoers NOPASSWD rules and the shutdown unmount loop are derived from
      this list.
    '';
  };

  config = {
    # A bindfs mount performed by a user-owned systemd unit crosses the LXC uid
    # boundary, so it needs sudo. Authorise exactly the argv the unit runs, and
    # only for shares declared in this list, so the grant cannot widen or drift.
    # The umount counterpart and the shutdown teardown below come from the same
    # list.
    security.sudo.extraRules = lib.mapAttrsToList
      (user: mounts: {
        users = [ user ];
        commands = map
          (command: {
            inherit command;
            options = [ "NOPASSWD" ];
          })
          (lib.unique (
            (map bindfsFor mounts)
            ++ (map (m: "${pkgs.util-linux}/bin/umount ${m.target}") mounts)
            ++ [ "/etc/nuke-lxc-from-orbit-on-shutdown.sh" ]
          ));
      })
      (lib.groupBy (m: m.user) bindMounts);

    users.groups.lxc-user.members = normalUserNames;

    virtualisation.lxc = {
      enable = true;
      unprivilegedContainers = true;

      defaultConfig = ''
        # Each lxc.* key may be specified once: repeated keys overwrite each other
        # rather than merging, so duplicated net/include blocks are a silent trap
        # (this file previously declared the net block three times).
        lxc.include = /run/current-system/sw/share/lxc/config/common.conf
        lxc.include = /run/current-system/sw/share/lxc/config/userns.conf

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

        # eth0 on the lxcbr0 bridge.
        #
        # hwaddr is pinned on purpose: guest NetworkManager keys its connection
        # profiles to the MAC, so a new random MAC on every start leaves the guest
        # with no matching profile. Give each container its own value here (or in
        # the container config) rather than relying on the random default.
        lxc.net.0.type = veth
        lxc.net.0.link = lxcbr0
        lxc.net.0.flags = up
        lxc.net.0.hwaddr = 00:16:3e:11:22:33

        # allow tun to be used in the lxc container:
        lxc.cgroup.devices.allow = c 10:200 rwm
        lxc.mount.entry = /dev/net dev/net none bind,create=dir 0 0
      '';
      usernetConfig = usernetLines;
      lxcfs.enable = true;
      # doesn't work research needed:
      # LXC's dnsmasq is started with --conf-file=/dev/null and gets its DHCP
      # options on the command line, so LXC_DHCP_CONFILE is never read and
      # dhcp-host reservations placed there are silently ignored. Per-container
      # addresses are therefore assigned in the container's own LXC config via
      # lxc.net.0.ipv4.address, not through a dnsmasq reservation.
      bridgeConfig = ''
        USE_LXC_BRIDGE="true"
        LXC_BRIDGE="lxcbr0"
        LXC_DOMAIN="lxc-net.local"
      '';
    };

    system.activationScripts.setLxcHomeACL.text = ''
      export PATH=${pkgs.acl}/bin:$PATH
      for home in ${homeDirsStr}; do
        user=$(basename "$home")                   # works even with /srv/users/alice
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
          ${lib.concatMapStrings (m: ''
            while ${pkgs.util-linux}/bin/umount ${m.target} ; do :; done
          '') bindMounts}
          ${pkgs.util-linux}/bin/mount | grep rootfs/mnt | ${pkgs.gawk}/bin/awk '{print $3}' | while read line ; do
            ${pkgs.procps}/bin/ps -ef | ${pkgs.gnugrep}/bin/grep "^100[0-9][0-9][0-9]" | ${pkgs.coreutils}/bin/tr -s " " | ${pkgs.coreutils}/bin/cut -f2 -d " " | ${pkgs.findutils}/bin/xargs -r ${pkgs.coreutils}/bin/kill -9
            ${lib.concatMapStrings (m: ''
              while ${pkgs.util-linux}/bin/umount ${m.target} ; do :; done
            '') bindMounts}
          done

          ${pkgs.procps}/bin/ps -ef | ${pkgs.gnugrep}/bin/grep "^100[0-9][0-9][0-9]" | ${pkgs.coreutils}/bin/tr -s " " | ${pkgs.coreutils}/bin/cut -f2 -d " " | ${pkgs.findutils}/bin/xargs -r ${pkgs.coreutils}/bin/kill -9
        done
      '';
      mode = "0755";
    };

    #environment.systemPackages = with pkgs; [
    #  bindfs
    #  skopeo
    #  umoci

    #  (writeShellScriptBin "reboot" ''
    #    /etc/nuke-lxc-from-orbit-on-shutdown.sh
    #    exec ${pkgs.systemd}/bin/reboot "$@"
    #  '')

    #  (writeShellScriptBin "poweroff" ''
    #    /etc/nuke-lxc-from-orbit-on-shutdown.sh
    #    exec ${pkgs.systemd}/bin/poweroff "$@"
    #  '')

    #  (writeShellScriptBin "shutdown" ''
    #    /etc/nuke-lxc-from-orbit-on-shutdown.sh
    #    exec ${pkgs.systemd}/bin/shutdown "$@"
    #  '')
    #];
  };
}
