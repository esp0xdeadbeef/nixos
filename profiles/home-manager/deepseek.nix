{ config, lib, ... }:
let
  apiKeyPath = "${config.home.homeDirectory}/.config/sops-nix/secrets/deepseek-api";
in
{
  sops.secrets."deepseek-api" = { };

  home.sessionVariables = {
    OPENAI_BASE_URL = "https://api.deepseek.com/v1";
  };

  home.file.".zshenv".text = ''
    # Add user bin to PATH for wrappers (e.g. claude)
    case ":$PATH:" in
      *:"$HOME/.local/bin":*) ;;
      *) export PATH="$HOME/.local/bin:$PATH" ;;
    esac

    # Source home-manager session variables (OPENAI_BASE_URL etc.)
    if [ -f "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh" ]; then
      . "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"
    fi

    if [ -f ${apiKeyPath} ]; then
      export DEEPSEEK_API_KEY="$(tr -d '\r\n' < ${apiKeyPath})"
    fi
  '';
  home.file.".profile".text = ''
    # Add user bin to PATH for wrappers (e.g. claude)
    case ":$PATH:" in
      *:"$HOME/.local/bin":*) ;;
      *) export PATH="$HOME/.local/bin:$PATH" ;;
    esac

    # Source home-manager session variables (OPENAI_BASE_URL etc.)
    if [ -f "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh" ]; then
      . "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"
    fi

    if [ -f ${apiKeyPath} ]; then
      export DEEPSEEK_API_KEY="$(tr -d '\r\n' < ${apiKeyPath})"
    fi
  '';

  home.file.".config/fish/conf.d/deepseek-api.fish".text = ''
    set -gx OPENAI_BASE_URL "https://api.deepseek.com/v1"

    if test -f ${apiKeyPath}
      set -gx DEEPSEEK_API_KEY (tr -d '\r\n' < ${apiKeyPath})
    end
  '';
}
