{ config, lib, pkgs, ... }:

let
  cfg = config.local.nix.githubAccessTokenFromGh;
in
{
  options.local.nix.githubAccessTokenFromGh.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Write a user nix.conf GitHub access token from gh auth during Home Manager activation.";
  };

  config = lib.mkIf cfg.enable {
    home.activation.nixGithubAccessToken = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      nix_config_dir="${config.xdg.configHome}/nix"
      nix_config="$nix_config_dir/nix.conf"
      token="$(${pkgs.gh}/bin/gh auth token 2>/dev/null || true)"

      if [ -z "$token" ]; then
        echo "gh is not authenticated; leaving $nix_config unchanged"
      elif [ -n "''${DRY_RUN_CMD:-}" ]; then
        echo "would write $nix_config with GitHub access token from gh"
      else
        mkdir -p "$nix_config_dir"
        chmod 700 "$nix_config_dir"
        tmp="$nix_config.tmp"
        {
          printf '%s\n' "extra-experimental-features = nix-command flakes"
          printf 'access-tokens = github.com=%s\n' "$token"
        } > "$tmp"
        chmod 600 "$tmp"
        mv "$tmp" "$nix_config"
      fi
    '';
  };
}
