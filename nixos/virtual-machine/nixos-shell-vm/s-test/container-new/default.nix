{
  config,
  pkgs,
  lib,
  vmRoot,
  outPath,
  ...
}:
{
  containers."${config.networking.hostName}-container-new" = {
    autoStart = true;
    privateNetwork = true;

    extraVeths = {
      #cnew-veth2.hostBridge = "vlan2";
      #cnew-veth3.hostBridge = "vlan3";
      #cnew-veth4.hostBridge = "vlan4";
      #cnew-veth5.hostBridge = "vlan5";
      #cnew-veth6.hostBridge = "vlan6";
      #cnew-veth7.hostBridge = "vlan7";
      #cnew-veth8.hostBridge = "vlan8";
      #cnew-veth9.hostBridge = "vlan9";

      cnew-veth10.hostBridge = "vlan10";

      # 20–29 Servers / infra
      cnew-veth20.hostBridge = "vlan20";

      # 30–39 User LAN
      cnew-veth30.hostBridge = "vlan30";

      # 40–49 Work / corp-segmented
      cnew-veth40.hostBridge = "vlan40";

      # 50–59 IoT / untrusted
      cnew-veth50.hostBridge = "vlan50";

      # 60–69 DMZ
      cnew-veth60.hostBridge = "vlan60";

      # 70–79 Lab / exploit / test
      cnew-veth70.hostBridge = "vlan70";

      # 80–89 Observability / monitoring
      cnew-veth80.hostBridge = "vlan80";

      # 90–99 Transit / router links
      cnew-veth90.hostBridge = "vlan90";

      # 1000+ WAN / ISP / upstream
      cnew-veth1010.hostBridge = "vlan1010";
    };

    bindMounts."/persist" = {
      hostPath = "/persist";
      isReadOnly = false;
    };
    # podman
    bindMounts."/var/lib/containers" = {
      hostPath = "/persist-state/var/lib/containers";
      isReadOnly = false;
    };
    # docker:
    bindMounts."/var/lib/docker" = {
      hostPath = "/persist-state/var/lib/docker";
      isReadOnly = false;
    };
    specialArgs = {
      inherit outPath;
      # you can also pass inputs/self/outputs/etc if you want
      # inherit inputs self outputs;
    };

    config =
      { outPath, ... }:
      {
        imports = [
          ./container-default.nix
        ];
      };

    additionalCapabilities = [
      "CAP_BPF"
      "CAP_PERFMON"
      "CAP_NET_ADMIN"
      "CAP_SYS_ADMIN"
    ];
    enableTun = true;
  };
}
