{ lib
, pkgs
, relativeRepo
, ...
}:

let
  githubTokenPath = "/run/secrets/gh-token";
in
{
  sops.secrets.gh-token = {
    sopsFile = relativeRepo.sourcePath "secrets/s-sigma-root.yaml";
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

      # A token that GitHub rejects is worse than no token at all: Nix always
      # authenticates when `access-tokens` is set, and a 401 downgrades the
      # fetch from "anonymous, allowed" to "authenticated, rejected".  Every
      # esp0xdeadbeef/* flake input is public, so a stale token turns a working
      # evaluation into `HTTP error 401 Bad credentials`.  Validate before
      # installing it, and treat an unverifiable token as unusable.
      token_ok=
      if [ -r "$token_file" ]; then
        token="$(tr -d '\r\n' < "$token_file")"
        if [ -n "$token" ]; then
          status="$(${pkgs.curl}/bin/curl -s -o /dev/null -w '%{http_code}' \
            --max-time 20 \
            -H "Authorization: token $token" \
            https://api.github.com/user || echo 000)"
          if [ "$status" = "200" ]; then
            token_ok=1
          else
            echo "warning: gh-token rejected by GitHub (HTTP $status); not writing access-tokens, flake inputs will be fetched anonymously" >&2
          fi
        fi
      fi

      if [ -n "''${token_ok-}" ]; then
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
      elif [ -e "$nix_config" ] && grep -q '^access-tokens[[:space:]]*=' "$nix_config"; then
        # Clear a previously installed stale token so the next fetch falls back
        # to anonymous access instead of failing with 401.
        tmp="$nix_config.tmp"
        grep -v -E '^access-tokens[[:space:]]*=' "$nix_config" > "$tmp" || true
        chmod 0600 "$tmp"
        mv "$tmp" "$nix_config"
      fi
    '';
  };
}
