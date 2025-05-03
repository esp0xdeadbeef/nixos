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
      # Grant container root (mapped to uid 100000) x access on /home/deadbeef
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
  environment.systemPackages = with pkgs; [
    # required for my (esp0xdeadbeef) lxc mounts
    bindfs

    # needed to export podman to lxc containers:
    skopeo
    umoci
  ];
}
