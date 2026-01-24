{ config, pkgs, ... }:
{
  # environment.etc."containers/containers.conf".text = ''
  #   [engine]
  #   init_path = "${pkgs.catatonit}/bin/catatonit"

  #   [network]
  #   cni_plugin_dirs = ["${pkgs.cni-plugins}/bin"]
  #   network_backend = "netavark"
  #   [containers]
  #   devices = [ "/dev/net/tun" ]
  #   default_capabilities = [
  #     "AUDIT_WRITE","CHOWN","DAC_OVERRIDE","FOWNER","FSETID","KILL",
  #     "MKNOD","NET_BIND_SERVICE","NET_RAW","SETFCAP","SETGID",
  #     "SETPCAP","SETUID","SYS_CHROOT","NET_ADMIN"
  #   ]
  # '';

  virtualisation.podman.enable = true;
}
