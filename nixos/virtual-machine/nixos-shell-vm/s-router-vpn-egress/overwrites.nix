{ config, lib, ... }:
{
  #containers = lib.mkMerge [
   # {
   #   "${config.networking.hostName}-container".extraVeths = lib.mkForce {
   #     lan3.hostBridge = "vlan3";
   #     lan7.hostBridge = "vlan7";
   #     lan1010.hostBridge = "vlan1010";
   #   };
   # }

   # {
   #   "${config.networking.hostName}-container".bindMounts."/run/secrets" = {
  #      hostPath = "/run/secrets";
  #    };
  #  }
  #];

  #sops.secrets.subnet-ipv6 = { };
}


