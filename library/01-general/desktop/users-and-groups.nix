{ config
, lib
, relativeRepo
, pkgs
, ...
}:
let
  primaryUser = config.local.users.primary.resolvedName;
  keyFor = host: lib.fileContents (relativeRepo.sourcePath "ssh-keys/deadbeef/${host}.pub");
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
      openssh.authorizedKeys.keys = [ ];
      packages = with pkgs; [ ];
    };
  };
}
