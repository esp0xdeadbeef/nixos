{
  config,
  lib,
  pkgs,
  ...
}:
let
  primaryUser = config.local.users.primary.resolvedName;
in
{
  local.users.primary.name = lib.mkDefault "deadbeef";

  #############################
  # User and Groups
  #############################
  users.users = lib.mkIf (primaryUser != null) {
    ${primaryUser} = {
      isNormalUser = true;
      linger = true; # not sure what this does...
      description = primaryUser;
      extraGroups = [
        "networkmanager"
        "wheel"
        "libvirtd"
        "video"
        "wireshark"
        "lxc-user"
      ];
      subGidRanges = [
        # # not what i want, but this is how you map 1:1 inside containers:
        # {
        #   startGid = 1000;
        #   count = 1;
        # }
        {
          startGid = 100000;
          count = 65536;
        }
      ];
      subUidRanges = [
        # # not what i want, but this is how you map 1:1 inside containers:
        # {
        #   startUid = 1000;
        #   count = 1;
        # }
        {
          startUid = 100000;
          count = 65536;
        }
      ];
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCa7PQ3hMgU3edhPZSY1eCTR0pwjfpO/Ywa5PXK8ieL2zlWTkD6C8UR+M0YsTlXw4XNy79Zl5JtDHqA043FCWcjikGV5mDRaZ/rS9Ew7+eEpXa+PwE18ckuQX9Pwq37kbJJAEf9A5ZtoEiDs/sa1+U0LzEF6iHqUwmHDV1PLXW84X0g+DJUqLDyF9FzkfdrwsRr1pkbwow83rHMIbIUGcCGgQCtfnPnlAdE8LbzxJRi7BSGJmIuG1xzGsYqJ4h3gCLiqmx7sIgGaOT66IxSi1xtEWBIxxRzkn85gnTIj8w1ydvT0AZPllguadvmkUiUif4QYE9CR7ik2mduh+d1CHln6Q2DZMnQOk6iM5TwHyYaPltuKx5w2jnXML9IIGlfYf8Kf/a+uD2uua+2PWBTtObrYoa6KX/nDY246qg3+eQ7o9HJD1s33WhLqYE7tpKuvU1cPXclOP0/C1UIUaj80o9niZmoNFRQHhp0IoNNs9LLL/mRE1/0QK3S2E5+wE7wSTc= deadbeef@l-esp"
      ];
      packages = with pkgs; [ ];
    };
  };
}
