{
  config,
  pkgs,
  lib,
  ...
}:

{
  environment.etc."qemu/bridge.conf".text = ''
    allow vmbr0
    allow vmbr1
    allow vmbr4
  '';

  boot.kernel.sysctl = {
    # DO NOT filter bridged traffic
    "net.bridge.bridge-nf-call-iptables" = 0;
    "net.bridge.bridge-nf-call-ip6tables" = 0;
    "net.bridge.bridge-nf-call-arptables" = 0;

    # DO NOT do reverse-path filtering on bridges/trunks
    "net.ipv4.conf.all.rp_filter" = 0;
    "net.ipv4.conf.default.rp_filter" = 0;
  };

  # Optional but recommended on hypervisors
  networking.firewall.enable = lib.mkForce false;
}
