{
  config,
  pkgs,
  lib,
  vmRoot,
  outPath,
  ...
}:
{
  containers."${config.networking.hostName}-container" = {
    autoStart = true;
    privateNetwork = true;

    extraVeths = {
      lan2.hostBridge = "vlan2";
      lan3.hostBridge = "vlan3";
      lan4.hostBridge = "vlan4";
      lan5.hostBridge = "vlan5";
      lan6.hostBridge = "vlan6";
      lan7.hostBridge = "vlan7";
      lan8.hostBridge = "vlan8";
      lan9.hostBridge = "vlan9";
      lan1010.hostBridge = "vlan1010";
    };

    bindMounts."/persist" = {
      hostPath = "/persist";
      isReadOnly = false;
    };
    bindMounts."/run/secrets" = {
      hostPath = "/run/secrets";
    };

    bindMounts."/var/lib/containers" = {
      hostPath = "/persist-state/var/lib/containers";
      isReadOnly = false;
    };

    bindMounts."/var/lib/docker" = {
      hostPath = "/persist-state/var/lib/docker";
      isReadOnly = false;
    };
    #bindMounts."/shared" = {
    #  hostPath = "/etc/shared";
    #  isReadOnly = true;
    #};

    config = vmRoot + "/container";

    additionalCapabilities = [
      "CAP_BPF"
      "CAP_PERFMON"
      "CAP_NET_ADMIN"
      "CAP_SYS_ADMIN"
    ];
    enableTun = true;
  };
  sops.secrets.subnet-ipv6 = { };
sops.secrets.vlan2-hostnames-servers-json = {
  sopsFile = "${outPath}/secrets/vlan2-hostnames-servers.json.age";
  format = "binary";
  path = "/run/secrets/vlan2-hostnames-servers.json";
};


}
