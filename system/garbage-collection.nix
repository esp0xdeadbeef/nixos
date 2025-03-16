{ config, pkgs, ... }: {
nix.gc = {
 automatic = true;
 persistent = false;
 dates = "daily";
 options = "--delete-older-than 30d";
};
}
