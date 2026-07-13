{ lib, outPath, ... }:

let
  githubTokenPath = "/run/secrets/gh-token";
in
{
  sops.secrets.gh-token = {
    sopsFile = "${outPath}/secrets/s-gamma.yaml";
    owner = "root";
    group = "root";
    mode = "0400";
    path = githubTokenPath;
  };

  system.activationScripts.writeRootNixGithubAccessToken = {
    deps = [ "setupSecrets" ];
    text = ''
      token_file=${lib.escapeShellArg githubTokenPath}
      nix_config_dir=/root/.config/nix
      nix_config="$nix_config_dir/nix.conf"

      if [ -r "$token_file" ]; then
        token="$(tr -d '\r\n' < "$token_file")"

        if [ -n "$token" ]; then
          install -d -m 0700 "$nix_config_dir"
          tmp="$nix_config.tmp"

          if [ -e "$nix_config" ]; then
            grep -v -E '^(extra-experimental-features|experimental-features|access-tokens)[[:space:]]*=' "$nix_config" > "$tmp" || true
          else
            : > "$tmp"
          fi

          {
            printf '%s\n' "extra-experimental-features = nix-command flakes"
            printf 'access-tokens = github.com=%s\n' "$token"
          } >> "$tmp"

          chmod 0600 "$tmp"
          mv "$tmp" "$nix_config"
        fi
      fi
    '';
  };
}
